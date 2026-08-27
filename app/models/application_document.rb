class ApplicationDocument

  require 'loofah'

  delegate :url_helpers, to: 'Rails.application.routes'

  class CleanupScrubber < Loofah::Scrubber
    def initialize
      super()
      @allowed_tags = %w[addr b br strong em i]
    end

    def scrub(node)
      # Only process element nodes
      if node.element? && !@allowed_tags.include?(node.name)
        node.remove # Remove the node if it's not in the allowed list
      end

      Loofah::Scrubber::CONTINUE
    end
  end

  class AuthorizationError < StandardError; end
  class MissingTenantContextError < StandardError; end
  class GridfilterError < StandardError; end
  class ExcelExporterError < StandardError; end

  # controls debug_puts / set to false for silence
  cattr_accessor :debug
  attr_accessor :skip_all_callbacks

  # to support mongoid_search if required
  def self.search_in(*args); end

  def self.collation_locale
    # uz is not supported by mongodb - fall back to default
    { uz: 'en' }.stringify_keys[I18n.locale.to_s] || I18n.locale.to_s
  end

  QUICKFILTER_MIN_LENGTH = 2
  QUICKFILTER_COLUMNS = []
  search_in *QUICKFILTER_COLUMNS

  # Overriding standard method from Mongoid::Search
  # since we don't want to trigger any callbacks here
  def index_keywords!
    search_fields.map do |index, fields|
      set(index => get_keywords(fields))
    end
  end

  def module
    self.class.module
  end
  def self.module
    to_s.tableize.dasherize
  end

  # these only work if the callbacks
  # are defined with `unless: :skip_all_callbacks?`
  def skip_all_callbacks?
    !!skip_all_callbacks
  end
  def skip_all_callbacks!
    self.skip_all_callbacks = true
  end

  # tries to find a translation of the attribute value in locale files (all keys downcased)
  # e.g. Actor#short_name -> "Users" - looks up `de.actor/short_name.users` -> "Benutzer"
  def translate_me(method_name, value)
    return nil if value.blank?
    _translate_me = "#{self.class.name.downcase}/#{method_name}.#{value.downcase}"
    _default = I18n.t("#{self.class.superclass.name.downcase}/#{method_name}.#{value.downcase}", default: value)
    I18n.t(_translate_me, default: _default)
  end

  # Helper to execute a given block
  # within a mongoDB transaction
  # Requires mongod to run as `replSet` !
  def self.with_transaction
    yield
    with_session do |session|
      session.start_transaction
      begin
        yield
        session.commit_transaction
      rescue => e
        session.abort_transaction
        raise e
      end
    end
  end

  # helper to migrate large number of records
  # in batches without timeouts
  def self.migrate_batch(num=10)
    batch_size(num).no_timeout
  end

  # helper to set a tenant_id in an activemodel chain
  # to be used further down
  def self.set_tenant_context(tenant_id=nil)
    @tenant_id = tenant_id
    criteria
  end

  # helper to set a tenant_id in an activemodel chain
  # to be used further down
  def self.tenant_context
    @tenant_id
  end

  # set aliases on fields for sorting
  # and gridfiltering
  # e.g. set_field_map(:field_count => "fields_total.#{current_tenant_id}")
  def self.set_field_map(_field_map={})
    @field_map = field_map.merge(_field_map)
    criteria
  end

  def self.field_map
    @field_map ||= {}
    @field_map[:id] ||= :_id
    @field_map
  end

  def self.filter_ids(ids=nil)
    if ids.is_a?(Array)
      criteria.where(:_id.in => ids)
    else
      criteria
    end
  end

  # default scopes
  def self.available
    criteria.not.where(deleted: true)
  end
  def self.deleted
    criteria.where(deleted: true)
  end
  def self.named(name)
    where(name: name.to_s.to_slug)
  end

  # Overridable method to define which fields are allowed for
  # gridfiltering
  def self.gridfilter_fields
    self.fields.keys.collect(&:to_sym)
  end

  # AG Gridfilter implementation
  # field map can optionally be supplied to map a normal field attribute
  # to a nested (e.g. tenant hash) or just a different field if used as an alias
  def self.gridfilter(filters)
    filters = JSON.parse(filters) if filters.is_a?(String)
    return criteria if filters.blank?

    raise GridfilterError.new(<<~ERR) unless filters.is_a?(Hash)
      Invalid gridfilter parameters. Object expected.
    ERR
    return criteria if filters.keys.empty?
    _criterias = filters.symbolize_keys.collect { |field, filter|
      field = field_map.with_indifferent_access.dig(field) || field
      _gridfilter_to_criteria(field, filter) if _gridfilter_field_valid?(field)
    }.compact
    raise GridfilterError.new(<<~ERR) if _criterias.empty?
      None of the provided fields is valid to filter by: >>#{filters.keys * ', '}<<.
      Valid field names are: 
        - `#{self.gridfilter_fields.join("\n  - ")}`
      Format needs to be one (or more) valid field name as key with an object as value.
      Example:
          { "field_name": { "filterType": "text", "type": "contains", "filter": "some text" }, ... }.
    ERR
    where('$and': _criterias)
  end

  def self.paginate(opts={})
    p = criteria
    p = p.page(opts[:page].to_i)
    p = p.per(opts[:per_page].to_i) if opts[:per_page].present?
    p = p.padding(opts[:padding].to_i) if opts[:padding].present? # dynamic page offset (skip = page*per_page+padding)
    p
  end

  def self.quickfilter(term, opts={})
    qf = criteria
    unless term.blank? || self::QUICKFILTER_COLUMNS.empty?
      return none if term.length < self::QUICKFILTER_MIN_LENGTH # returning `none` criteria prevents hitting the db
      index = opts[:index] ||= :_keywords # allows searching in a specific index
      match = opts[:match] ||= :all # can be :any
      relevant_search = opts[:relevant_search] || false # set to true to return relevancy data
      regex_search = opts[:regex] ? true : false # auto enable if regex provided
      regex = opts[:regex] # allows regex searching in indexed words (slower)
      qf = qf.and.full_text_search(term,
        allow_empty_search: true,
        match: match,
        index: index,
        relevant_search:relevant_search,
        regex_search: regex_search,
        regex: regex)
    end
    qf
  end

  # Takes the requested associations list to be included
  # checks if they're valid and makes a more efficient
  # eager loading.
  # Use in controller via
  #    .auto_includes(json_api_options[:include])
  def self.auto_includes(json_api_options_include, serializer=nil)
    unless json_api_options_include.try(:any?)
      criteria
    else
      criteria.includes(*json_api_options_include.collect(&:to_sym).collect do |_assoc|
        serializer.relationships_to_serialize.keys.include?(_assoc) && reflect_on_association(_assoc) ? 
          _assoc.to_sym : nil
      end.compact)
    end
  end

  def self.fallback_default_order
    criteria.order(updated_at: -1)
  end

  # sorting logic, via collation true the collation_locale will be set
  # which results in proper handling of text in the current locale
  #     numericOrdering: true
  # will make sure numbers as string values will be sorted logically
  def self.sorting(json_string, collation: true)
    sorts = JSON.parse(json_string) rescue nil
    return fallback_default_order if !sorts.is_a?(Array) || sorts.empty?

    _reorder = (sorts.collect do |sort|
      field = sort['property']
      field = field_map.with_indifferent_access.dig(field) || field
      [field.to_sym, sort['direction'].eql?('ASC') ? 1 : -1]
    end << [:id, 1]).uniq # always sort by id as last step

    _sorting = reorder(**_reorder.to_h)

    collation ? _sorting.collation(locale: collation_locale, numericOrdering: true) : _sorting
  end

  def filename(extension=nil)
    [self.class.model_name.human(count:1), extension].compact.uniq.join('.')
  end

  # Activates MongoDB logging on console for development
  def self.logs!(status=true)
    Mongoid.logger = Logger.new($stdout)
    Mongo::Logger.logger = Logger.new($stdout)
    if !status
      Mongoid.logger.level = :warn
      Mongo::Logger.logger.level = :warn
    end
    !!status
  end

  def self.ensure_base64(file)
    case file
      when String then
        file
      when File, StringIO, Base64StringIO, ActionDispatch::Http::UploadedFile then
        _file_data = file.open.read.force_encoding('utf-8')
        file.close
        "data:#{file.content_type};base64,#{Base64.encode64(_file_data)}".strip
      else
        nil
    end
  end

  def self.sample
    return nil unless respond_to?(:find)

    where(:_id => sample_id).first
  end

  def self.samples(size)
    return [nil] unless respond_to?(:find)

    where(:_id.in => sample_ids(size)).to_a
  end

  def self.sample_id
    sample_ids(1)[0]
  end

  def self.sample_ids(size)
    return [] unless respond_to?(:collection)
    # must fetch via pluck(:_id) as some chained criteria
    # might get lost otherwise
    collection.aggregate(
      [
        {
          '$match': {
            '_id': {
              '$in': pluck(:_id)
            }
          }
        },
        { '$sample' => { 'size' => size } },
        { '$project' => { _id: true } }
      ]
    ).to_a.pluck('_id')
  end

  private
  # The _gridfilter_* methods implement server side filtering with AG-Grid style
  # filterModel data by turning these into Mongoid syntax.
  # See https://www.ag-grid.com/javascript-grid-filtering/
  # > The best way to understand what the filter models look like is to set a 
  # > filter via the UI and call api.getFilterModel().
  # > Then observe what the filter model looks like for different variations of
  # > the filter.

  # Decide if the requested field is allowed for filtering.
  # Default is all existing fields of the collection are valid.
  # @return {Boolean} indicating if the field can be filtered
  def self._gridfilter_field_valid?(field)
    return true if gridfilter_fields.include?(field.to_sym)
    field = field.to_s.split('.').first # to allow dynamically nested field contents
    gridfilter_fields.include?(field.to_sym)
  end

  # Formats a (filter type object_id) condition type into the Mongoid equivalent
  def self._gridfilter_object_id_to_criterion_value(condition_type, condition_value)
    case condition_type.to_s.underscore
    when 'equals'
      BSON::ObjectId(condition_value.to_s)
    when 'not_equal'
      { '$ne' => BSON::ObjectId(condition_value.to_s) }
    when 'in_set'
      { '$in': ensure_bson(condition_value) }
    when 'not_in_set'
      { '$nin': ensure_bson(condition_value) }
    when 'greater_than'
      { '$gt' => BSON::ObjectId(condition_value.to_s) }
    when 'greater_than_or_equal'
      { '$gte' => BSON::ObjectId(condition_value.to_s) }
    when 'less_than'
      { '$lt' => BSON::ObjectId(condition_value.to_s) }
    when 'less_than_or_equal'
      { '$lte' => BSON::ObjectId(condition_value.to_s) }
    when 'empty'
      { '$eq': nil }
    when 'not_empty'
      { '$ne': nil }
    else
      raise GridfilterError.new("unsupported condition_type #{condition_type}")
    end
  end

  # Formats a (filter type text) condition type into the Mongoid equivalent
  def self._gridfilter_text_to_criterion_value(condition_type, condition_value, field: nil)
    case condition_type.to_s.underscore
    when 'contains'
      Regexp.new(Regexp.escape(condition_value.to_s), Regexp::IGNORECASE)
    when 'not_contains'
      { '$not' => Regexp.new(Regexp.escape(condition_value.to_s), Regexp::IGNORECASE) }
    when 'starts_with'
      # a plain "^..." regexp works but can't use an index range scan and does
      # not mix with numericOrdering: true - use a collated range instead,
      # then fold the matching _id's back into a normal selector
      criteria_starts_with = where(field => {
                                     '$gte': condition_value.to_s,
                                     '$lt': "#{condition_value}￿"
                                   })
      where(:_id.in => criteria_starts_with.collation(locale: collation_locale, strength: 1).pluck(:_id))
    when 'ends_with'
      Regexp.new("#{Regexp.escape(condition_value.to_s)}$", Regexp::IGNORECASE)
    when 'equals'
      condition_value.to_s
    when 'not_equal'
      { '$ne' => condition_value.to_s }
    when 'matches'
      Regexp.new("^#{Regexp.escape(condition_value.to_s)}$", Regexp::IGNORECASE)
    when 'not_matches'
      { '$not' => Regexp.new("^#{Regexp.escape(condition_value.to_s)}$", Regexp::IGNORECASE) }
    when 'in_set'
      { '$in': [condition_value].flatten.select{|_| [NilClass, String].include?(_.class) } }
    when 'not_in_set'
      { '$nin': [condition_value].flatten.select{|_| [NilClass, String].include?(_.class) } }
    when 'empty'
      { '$in': [nil, ''] }
    when 'not_empty'
      { '$nin': [nil, ''] }
    else
      raise GridfilterError.new("unsupported condition_type #{condition_type}")
    end
  end

  # Formats a (filter type number) condition type into the Mongoid equivalent.
  #
  # nil/unset documents only fold into the matching side of the comparison
  # when `field` declares a *numeric* Mongoid default - that default IS what
  # nil means there. A field with no declared default (or a non-numeric one)
  # gets the strict numeric selector, with no fold - we don't know what nil
  # means there, so we don't guess. Same reasoning as
  # `_gridfilter_bool_to_criterion_value` below, for numeric fields.
  def self._gridfilter_number_to_criterion_value(condition_type, condition_value, condition_value2, field: nil)
    default_val = _gridfilter_field_default_val(field)
    fold_value = default_val.is_a?(Numeric) ? default_val : nil

    _with_null = fold_value && condition_value == fold_value
    _cond = case condition_type.to_s.underscore
            when 'equals'
              { '$eq' => condition_value }
            when 'not_equal'
              { '$ne' => condition_value }
            when 'less_than'
              _with_null = fold_value && fold_value < condition_value
              { '$lt' => condition_value }
            when 'less_than_or_equal'
              _with_null = fold_value && fold_value <= condition_value
              { '$lte' => condition_value }
            when 'greater_than'
              _with_null = fold_value && fold_value > condition_value
              { '$gt' => condition_value }
            when 'greater_than_or_equal'
              _with_null = fold_value && fold_value >= condition_value
              { '$gte' => condition_value }
            when 'in_range'
              raise GridfilterError.new("missing condition filterTo for #{condition_type.inspect}") unless condition_value2.present?
              _with_null = fold_value && (condition_value..condition_value2).include?(fold_value)
              { '$gte' => condition_value, '$lte' => condition_value2 }
            when 'in_set'
              _set = [condition_value].flatten.select{|_| [NilClass, Integer, Float].include?(_.class) }
              if fold_value && _set.include?(fold_value)
                _with_null = false
                _set << nil
              end
              { '$in': _set }
            when 'not_in_set'
              _set = [condition_value].flatten.select{|_| [NilClass, Integer, Float].include?(_.class) }
              if fold_value && _set.include?(fold_value)
                _with_null = false
                _set << nil
              end
              { '$nin': _set }
            else
              raise GridfilterError.new("unsupported condition_type #{condition_type}")
            end
    return _cond unless _with_null

    if condition_type.to_s.underscore.start_with?('not')
      [[_cond, { '$ne' => nil }], '$and']
    else
      [[_cond, { '$eq' => nil }], '$or']
    end
  end

  # Formats a (filter type date) condition type into the Mongoid equivalent
  def self._gridfilter_date_to_criterion_value(condition_type, condition_value, condition_value2)
    date_from = Date.parse(condition_value) rescue (raise GridfilterError.new("invalid dateFrom (#{condition_value}) for #{condition_type}"))

    case condition_type.to_s.underscore
    when 'equals'
      # use 24h period to support datetime data
      date_from.beginning_of_day..date_from.end_of_day
    when 'not_equal'
      { '$not' => date_from.beginning_of_day..date_from.end_of_day }
    when 'less_than'
      { '$lt' => date_from.beginning_of_day }
    when 'greater_than'
      { '$gt' => date_from.end_of_day }
    when 'in_range'
      raise GridfilterError.new("missing condition dateTo for #{condition_type.inspect}") unless condition_value2.present?
      date_to = Date.parse(condition_value2) rescue (raise GridfilterError.new("invalid dateTo (#{condition_value2}) for #{condition_type}"))
      { '$gte' => date_from.beginning_of_day, '$lte' => date_to.end_of_day }
    else
      raise GridfilterError.new("unsupported condition_type #{condition_type}")
    end
  end

  # Formats a (filter type datetime) condition type into the Mongoid equivalent
  def self._gridfilter_datetime_to_criterion_value(condition_type, condition_value, condition_value2)
    date_time_from = Time.parse(condition_value) rescue (raise GridfilterError.new("invalid dateTimeFrom (#{condition_value}) for #{condition_type}"))

    case condition_type.to_s.underscore
    when 'equals'
      date_time_from
    when 'not_equal'
      { '$not' => date_time_from }
    when 'less_than'
      { '$lt' => date_time_from }
    when 'greater_than'
      { '$gt' => date_time_from }
    when 'in_range'
      raise GridfilterError.new("missing condition dateTimeTo for #{condition_type.inspect}") unless condition_value2.present?
      date_time_to = Time.parse(condition_value2) rescue (raise GridfilterError.new("invalid dateTimeTo (#{condition_value2}) for #{condition_type}"))
      { '$gte' => date_time_from, '$lte' => date_time_to }
    else
      raise GridfilterError.new("unsupported condition_type #{condition_type}")
    end
  end

  # Formats a (filter type bool) condition type into the Mongoid equivalent.
  #
  # `field` (when it names a plain, non-dotted field on this class) is used to
  # look up that field's own Mongoid default. Only a field that explicitly
  # declares `default: false` / `default: true` gets nil/unset documents
  # folded into the matching side of the comparison - a field with NO
  # declared default keeps the original bare-boolean behavior (unset never
  # matches either side).
  def self._gridfilter_bool_to_criterion_value(condition_type, condition_value, field: nil)
    condition_value = condition_value.to_s.downcase
    truthy = %w(true yes).include? condition_value
    non_truthy = %w(false no).include? condition_value
    unless truthy || non_truthy
      raise GridfilterError.new("invalid value (#{condition_value}) for #{condition_type}. accepted: true/yes or false/no")
    end

    case condition_type.to_s.underscore
    when 'before_today', 'after_today', 'before_now', 'after_now'
      _type = if condition_type.to_s.underscore.starts_with?('before_')
                truthy ? 'less_than' : 'greater_than'
              else
                non_truthy ? 'less_than' : 'greater_than'
              end
      _value = condition_type.to_s.underscore.ends_with?('_now') ? Time.now : Date.today
      _gridfilter_datetime_to_criterion_value(_type, _value.to_fs(:db), nil)
    when 'equals'
      _gridfilter_bool_equals_criterion(truthy, field)
    when 'not_equal'
      # "not_equal x" is exactly "equals !x" once nil-folding depends on the
      # field's default rather than a hardcoded direction.
      _gridfilter_bool_equals_criterion(non_truthy, field)
    else
      raise GridfilterError.new("unsupported condition_type #{condition_type}")
    end
  end

  # Shared by every default-aware gridfilter comparison
  # (`_gridfilter_bool_equals_criterion`, `_gridfilter_number_to_criterion_value`):
  # looks up `field`'s own declared Mongoid default, or nil if that can't be
  # determined.
  #
  # Only trusted for a plain, non-dotted field name on THIS class. `fields`
  # holds this class's own top-level Mongoid fields only - a dotted path
  # (e.g. an embedded doc's "statistics.count") isn't in there and resolves
  # to nil here, same as "no declared default": the fold simply doesn't fire
  # for it, rather than guessing wrong.
  def self._gridfilter_field_default_val(field)
    field.present? ? fields[field.to_s]&.default_val : nil
  end

  # `want` is the boolean value the caller asks the field to equal. See
  # `_gridfilter_bool_to_criterion_value` above for why nil-folding is gated
  # on the field's own declared default instead of being unconditional.
  def self._gridfilter_bool_equals_criterion(want, field)
    default_val = _gridfilter_field_default_val(field)

    # `$in => [x, nil]` rather than `$ne => !x`: for a boolean field the two
    # are equivalent, but `$ne` cannot use an index range scan while `$in` on
    # an explicit short value list can.
    case default_val
    when true
      want ? { '$in' => [true, nil] } : false
    when false
      want ? true : { '$in' => [false, nil] }
    else
      want
    end
  end

  # Coerces a single `number` gridfilter scalar value for `field` to the
  # field's own declared Mongoid type (Float/BigDecimal fields via `.to_f`,
  # everything else via `.to_i`) so it compares as the right type regardless
  # of whether it arrived as a String or a bare JSON number.
  def self._gridfilter_number_coerce(value, field: nil)
    return value if value.nil?
    unless value.is_a?(Numeric) || value.is_a?(String)
      raise GridfilterError.new("invalid numeric filter value #{value.inspect}")
    end

    field_type = field.present? ? fields[field.to_s]&.type : nil
    [Float, BigDecimal].include?(field_type) ? value.to_f : value.to_i
  end

  # Same coercion as `_gridfilter_number_coerce`, but for one element of an
  # `in_set`/`not_in_set` filter array. A garbage element is passed through
  # unchanged - `_gridfilter_number_to_criterion_value`'s own whitelist then
  # silently drops it.
  def self._gridfilter_number_coerce_set_element(value, field: nil)
    return value unless value.nil? || value.is_a?(Numeric) || value.is_a?(String)
    _gridfilter_number_coerce(value, field: field)
  end

  # Raises when `condition` carries any key not in `allowed_options`.
  def self._gridfilter_check_condition(field_name, condition, allowed_options: [])
    _unsupported_options = condition.keys - allowed_options
    raise GridfilterError.new(<<~ERR.chomp) if _unsupported_options.any?
      at field: '#{field_name}'
      we detected unsupported options: '#{_unsupported_options.join(', ')}' -
      valid options are: '#{allowed_options.join(', ')}'
    ERR
    true
  end

  # Turns a specific condition into a Mongoid Criterion
  def self._gridfilter_condition_to_criterion(field, condition)
    condition = condition.symbolize_keys
    raise GridfilterError.new("missing condition type within #{condition.inspect}") unless condition[:type].present?

    case condition[:type].to_s.underscore
    when 'empty'
      case condition[:filterType].to_s.downcase
      when 'text'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        criterion = { '$in' => [nil, ''] } # DOES NOT WORK WITH TIME FIELDS
      when 'array'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        criterion = { '$in' => [nil, []] }
      when 'datetime'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type dateTimeFrom)
        criterion = { '$eq' => nil }
      when 'date'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type dateFrom)
        criterion = { '$eq' => nil }
      else
        criterion = { '$eq' => nil }
      end
    when 'not_empty'
      case condition[:filterType].to_s.downcase
      when 'text'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        criterion = { '$nin' => [nil, ''] } # DOES NOT WORK WITH TIME FIELDS
      when 'array'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        criterion = { '$exists': true, '$not': { '$size': 0 } }
      when 'datetime'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type dateTimeFrom)
        criterion = { '$ne' => nil }
      when 'date'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type dateFrom)
        criterion = { '$ne' => nil }
      else
        criterion = { '$ne' => nil }
      end
    else
      raise GridfilterError.new("missing condition filterType within #{condition.inspect}") unless condition[:filterType].present?
      case condition[:filterType].to_s.downcase
      when 'object_id'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        case condition[:type].to_s.underscore
        when 'in_set', 'not_in_set'
          raise GridfilterError.new("missing condition filter array within #{condition.inspect}") unless ensure_bson(condition[:filter]).is_a?(Array)
        else
          raise GridfilterError.new("missing condition filter within #{condition.inspect}") unless condition[:filter].is_a?(String) || condition[:type] == 'empty'
        end
        criterion = _gridfilter_object_id_to_criterion_value(condition[:type], condition[:filter])
      when 'text'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        case condition[:type].to_s.underscore
        when 'in_set', 'not_in_set'
          raise GridfilterError.new("missing condition filter array within #{condition.inspect}") unless condition[:filter].is_a?(Array)
        else
          raise GridfilterError.new("missing condition filter within #{condition.inspect}") unless condition[:filter].is_a?(String) || condition[:type] == 'empty'
        end
        criterion = _gridfilter_text_to_criterion_value(condition[:type], condition[:filter], field: field)
      when 'number'
        case condition[:type].to_s.underscore
        when 'in_set', 'not_in_set'
          _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
          raise GridfilterError.new("missing condition filter array within #{condition.inspect}") unless condition[:filter].is_a?(Array)
          _filter_value = condition[:filter].collect { |v| _gridfilter_number_coerce_set_element(v, field: field) }
        else
          _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter filterTo)
          raise GridfilterError.new("missing condition filter within #{condition.inspect}") unless condition[:filter].present?
          _filter_value = _gridfilter_number_coerce(condition[:filter], field: field)
        end
        _filter_to_value = _gridfilter_number_coerce(condition[:filterTo], field: field)
        criterion = _gridfilter_number_to_criterion_value(condition[:type], _filter_value, _filter_to_value, field: field)
      when 'date'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type dateFrom dateTo)
        raise GridfilterError.new("missing condition dateFrom within #{condition.inspect}") unless condition[:dateFrom].present?
        criterion = _gridfilter_date_to_criterion_value(condition[:type], condition[:dateFrom], condition[:dateTo])
      when 'datetime'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type dateTimeFrom dateTimeTo)
        raise GridfilterError.new("missing condition dateTimeFrom within #{condition.inspect}") unless condition[:dateTimeFrom].present?
        criterion = _gridfilter_datetime_to_criterion_value(condition[:type], condition[:dateTimeFrom], condition[:dateTimeTo])
      when 'bool'
        _gridfilter_check_condition field, condition, allowed_options: %i(filterType type filter)
        criterion = _gridfilter_bool_to_criterion_value(condition[:type], condition[:filter], field: field)
      else
        raise GridfilterError.new("unsupported condition filterType #{condition[:filterType]}")
      end
    end

    if criterion.is_a?(Mongoid::Criteria)
      criterion.selector
    elsif criterion.is_a?(Array)
      _conditions, _and_or = criterion
      {
        _and_or => _conditions.collect { |c| c.is_a?(Mongoid::Criteria) ? c.selector : { field => c } }
      }
    else
      { field => criterion }
    end
  end

  # Turns a single field filter defintion (single or joined with second condition)
  # into separate Mongoid Criterions and joins these into a Mongoid Critera
  def self._gridfilter_to_criteria(field, filter)
    filter = filter.symbolize_keys
    unless filter[:operator].present?
      # single criteria
      return _gridfilter_condition_to_criterion(field, filter)
    end
    {
      # two criterias joined by OR/AND
      (filter[:operator].to_s.upcase.eql?('OR') ? '$or' : '$and') => [
        _gridfilter_condition_to_criterion(field, filter[:condition1]),
        _gridfilter_condition_to_criterion(field, filter[:condition2])
      ]
    }
  end

  def list_associations
    @list_associations ||= begin
      self.class.reflect_on_all_associations.collect(&:name)
    end
  end

  def self.exportable_columns
    @exportable_columns ||= begin
      _exportable_columns = self::EXPORTABLE_COLUMNS
      _exportable_columns = instance_exec(&_exportable_columns.to_proc) if _exportable_columns.is_a?(Proc)
      _exportable_columns
    end
  end

  def self.xlsx_allowed?
    return exportable_columns.any? if exportable_columns.is_a?(Array)
    exportable_columns.keys.any? rescue false
  end

  def self.as_xlsx(api_params)
    to_xlsx(
      columns: exportable_columns,
      only_columns: api_params.dig(:export, :columns)||[],
      headers: api_params.dig(:export, :header)||{}
    )
  end

  # Create Excel Sheet
  def self.to_xlsx(package: Axlsx::Package.new, columns: exportable_columns, only_columns: [], headers: {})
    columns = columns.inject({}) {|h,v| h[v]=:standard; h } if columns.is_a?(Array)
    columns = columns.stringify_keys
    _exportable_columns = columns.keys
    raise ExcelExporterError.new('EXPORTABLE_COLUMNS needs to be a Hash or an Array') unless _exportable_columns.is_a?(Array)
    if only_columns.any? # allow subset of columns of EXPORTABLE_COLUMNS
      ## To get the exportable column in the order of the selected columns
      _exportable_columns = only_columns.map(&:to_s) & _exportable_columns
    end

    p = package
    wb = p.workbook
    styles = xlsx_styles(wb)
    wb.add_worksheet(:name => model_name.human) do |sheet|
      column_titles = _exportable_columns.collect{|col| headers[col]||human_attribute_name(col)||col }
      column_title_styles = []
      _exportable_columns.each_with_index.collect do |col, col_idx|
        custom_column_style = columns.dig(col, :header, :style) rescue false
        if custom_column_style
          column_title_styles[col_idx] ||= wb.styles.add_style(xslx_style_defs[:h1].merge(custom_column_style))
        else
          column_title_styles[col_idx] ||= styles[:h1]
        end
      end
      column_styles = _exportable_columns.collect{|col| xlsx_auto_format(col, styles: styles, columns: columns, workbook: wb) }
      custom_styles = {}
      header_heights = _exportable_columns.collect{|col| columns.dig(col, :header, :height)} rescue []
      # set header row
      sheet.add_row column_titles, style: column_title_styles, height: header_heights.compact.max

      sheet.sheet_view.pane do |pane|
        xlsx_configure_pane pane
      end
      # collect data
      sheet.column_widths *_exportable_columns.collect{|col| (columns.dig(col, :width) rescue nil) } # nil == autowidth (does not really work vOv)

      column_types = _exportable_columns.collect{|col| xlsx_auto_type(col, styles: styles, columns: columns, workbook: wb) }
      row_column_styles = []
      row_heights = []
      formatters = {}
      _exportable_columns.each_with_index.collect do |col, col_idx|
        custom_column_style = columns.dig(col, :style) rescue false
        row_heights << columns.dig(col, :height) rescue nil
        row_heights.compact!
        if custom_column_style
          row_column_styles[col_idx] = custom_styles[col] ||= wb.styles.add_style(xlsx_global_styles.merge(custom_column_style))
        else
          row_column_styles[col_idx] = column_styles[col_idx]
        end
        formatters[col] = columns.dig(col, :formatter) rescue nil
        formatters[col] = columns[col] if columns[col].is_a?(Proc)
      end
      row_height = row_heights.compact.max

      processed = []
      #Parallel.each_with_index(all, in_threads: 4) do |record, idx|
      all.each_with_index do |record, idx|
        processed[idx] = _exportable_columns.each_with_index.collect do |col, col_idx|
          formatter = formatters[col]
          row_value = (formatter.present? ? record.instance_exec(record.try(col), &formatter) : record.try(col))
          row_value
        end
      end

      processed.each do |row_data|
        # switch the :auto type to our own logic to prevent '123e456' being turned to Infinity and breaking the file
        row_data.each_with_index do |row_value, col_idx|
          column_types[col_idx] = xlsx_auto_type_by_value(row_value) if column_types[col_idx].eql?(:auto)
        end if column_types.include?(:auto)

        sheet.add_row row_data, style: row_column_styles, types: column_types, height: row_height
      end

    end
    # required for interop with non MS Office
    p.use_shared_strings = true
    p
  end

  # Helper to find duplicates
  #    check_dupes :foo_id, :bar_id
  # @param fields Array of field combinations that should be unique
  # @return Hash with duplicate count and the _id's of values having duplicate
  def self.check_dupes(*fields)
    collection.aggregate([
      { "$match": criteria.selector },
      { "$group" => {
        _id: fields.flatten.collect {|f| [f.to_s, "$#{f}"] }.to_h,
        recordIds: { "$addToSet" => "$_id" },
        count: { "$sum" => 1 }
      }},
      { "$match" => {
        count: { "$gt" => 1 }
      }}
    ])
  end

  # Define the global styles used for all default styles and
  # base custom styles on this (can be overriden)
  def self.xlsx_global_styles
    { sz: 12, font_name: 'Calibri' }
  end

  def self.xslx_style_defs
    {
      standard:     { alignment: { wrap_text: true } },
      h1:           { b: true, bold: true, alignment: { horizontal: :left }, border: { style: :medium, color: "00", edges: [:bottom] } },
      date:         { format_code: 'dd.mm.yyyy' },
      datetime:     { format_code: 'dd.mm.yyyy hh:mm' },
      time:         { format_code: 'hh:mm' },
      integer:      { format_code: '#' },
      decimal:      { format_code: '#,##0.00' },
      currency:     { format_code: '#,###,##0 €' },
      border_thin:  { border: Axlsx::STYLE_THIN_BORDER },
      percent:      { num_fmt: Axlsx::NUM_FMT_PERCENT },
      boolean:      { b: true, bold: true }
    }
  end

  # override this to customize locked rows/columns
  def self.xlsx_configure_pane(pane)
    # lock first row
    pane.top_left_cell = "A2"
    pane.state = :frozen
    pane.x_split = 0
    pane.y_split = 1
    pane.active_pane = :bottom_right
  end

  # Define the default styles
  def self.xlsx_styles(workbook, style: {})
    workbook.styles do |s|
      xslx_style_defs.each do |name, style|
        style[name] ||= s.add_style xlsx_global_styles.merge(style)
      end
    end
    style
  end

  # A column can be either a symbol of one of the standard styles
  # or a hash with the `:style` key to define a custom style
  def self.xlsx_auto_format(col, columns:nil, workbook:nil, styles: {})
    default_style = styles[:standard] || nil
    if columns[col].present?
      if columns[col].is_a?(Hash)
        col_style = columns[col][:style]
        if col_style.is_a?(Hash) # add this custom style to workbook
          workbook.styles do |s|
            styles["_custom_#{col}"] ||= s.add_style xlsx_global_styles.merge(col_style)
          end
          return styles["_custom_#{col}"]
        else
          return styles[col_style] || default_style
        end
      else
        return styles[columns[col]] || default_style
      end
    end
    default_style
  end

  # taken from 
  # https://stackoverflow.com/questions/30620168/writing-a-number-as-string-in-ruby-axlsx-library
  def self.xlsx_auto_type_by_value(v)
    if v.is_a?(Date)
      :date
    elsif v.is_a?(Time)
      :time
    elsif v.is_a?(TrueClass) || v.is_a?(FalseClass)
      :boolean
    elsif v.to_s =~ /\A[+-]?\d+?\Z/ #numeric
      :integer
    # only detect floats that don't come as a string or '123e456' turns to Infinity
    elsif !v.is_a?(String) && v.to_s =~ /\A[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?\Z/ #float
      :float
    elsif v.to_s =~/\A(-?(?:[1-9][0-9]*)?[0-9]{4})-(1[0-2]|0[1-9])-(3[0-1]|0[1-9]|[1-2][0-9])T(2[0-3]|[0-1][0-9]):([0-5][0-9]):([0-5][0-9])(\.[0-9]+)?(Z|[+-](?:2[0-3]|[0-1][0-9]):[0-5][0-9])?\Z/
      :iso_8601
    else
      :string
    end
  end

  # A column can be either a symbol of one of the standard types
  # or a hash with the `:type` key to define a specific type
  # setting :auto will do auto detection for each and every value
  def self.xlsx_auto_type(col, columns:nil, workbook:nil, styles: {})
    default_type = :auto
    if columns[col].present?
      if columns[col].is_a?(Hash)
        return columns[col][:type] || default_type
      end
    end
    default_type
  end

  # this implements what #has_secure_token does for ActiveRecord
  def self.generate_unique_secure_token
    SecureRandom.base58(24)
  end
  def self.has_secure_token(attribute = :token)
    # Load securerandom only when has_secure_token is used.
    require "active_support/core_ext/securerandom"
    field attribute.to_sym, type: String
    define_method("regenerate_#{attribute}") { update! attribute => self.class.generate_unique_secure_token }
    before_create { send("#{attribute}=", self.class.generate_unique_secure_token) unless send("#{attribute}?") }
  end

  def self.cleanup_html(unsafe_html)
    return nil unless unsafe_html.present?
    _html = Loofah.scrub_fragment(unsafe_html, self::cleanup_html_scrubber).to_s.strip
    _html.present? ? _html : nil
  end

  # pre defined scrubbing stragegy of loofah
  # will remove unsafe tags and attributes
  def self.cleanup_html_scrubber
    # custom scrubber since `:whitewash` was too restrictive
    CleanupScrubber.new
  end

  # turns string ids into an Array of BSON::ObjectId's
  def self.ensure_bson(ids)
    [ids].flatten.compact.collect { |id| id.to_s.split(',') }.flatten.uniq.collect { |id| BSON::ObjectId id.to_s.strip }
  end

  def self.redo_indexes
    remove_indexes
    create_indexes
  end

  def self.console?
    !!((defined?(Rails::Console) rescue false) && !debug.eql?(false))
  end

  def console?
    self.class.console?
  end

  def self.debug_puts(*args)
    puts *args if console?
  end
  def debug_puts(*args)
    puts *args if console?
  end
  def self.debug_ap(*args)
    ap *args if console?
  end
  def debug_ap(*args)
    ap *args if console?
  end

end
