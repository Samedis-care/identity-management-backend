# Below is a list of valid types for fields.
# - Array
# - BigDecimal
# - Boolean
# - Date
# - DateTime
# - Float
# - Hash
# - Integer
# - BSON::ObjectId
# - Moped::BSON::Binary
# - Range
# - Regexp
# - String
# - Symbol
# - Time
# - TimeWithZone
class Actor < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Tree
  include Mongoid::Tree::Traversal
  include Mongoid::Search
  Shrine.plugin :mongoid
  include ActorImageUploader::Attachment.new(:image)

  attr_accessor :actor_type

  TYPES = %i(
    mapping
    container
    apps
    app
    tenants
    organization
    tenant
    group
    ou
    user
    enterprise
  ).freeze
  DEFAULTS = YAML.load_file('config/actor_defaults.yml')

  MAPPABLE_TYPES = %i(user group ou position tenant).freeze
  QUICKFILTER_COLUMNS = %i(short_name name).freeze
  search_in(*QUICKFILTER_COLUMNS)

  # fix mongoid-tree descendants to be used as
  # chained criteria for new instances
  # e.g. descendants.new would break because parent_ids must be Array
  def descendants
    base_class.where(:parent_ids.in => [id])
  end

  strip_attributes collapse_spaces: true

  has_one :user, class_name: '::User', inverse_of: :actor, dependent: :destroy
  has_and_belongs_to_many :roles, inverse_of: nil # this creates role_ids on the actor # rubocop:disable Rails/HasAndBelongsToMany

  belongs_to :map_actor, class_name: Actor, optional: true
  belongs_to :template_actor, inverse_of: :templates, class_name: Actor, optional: true
  has_many :templates, inverse_of: :template_actor, class_name: Actor

  has_many :mappings, class_name: 'Actors::Mapping', foreign_key: :parent_id, inverse_of: :mapped_into

  validate :proper_name
  validates :name, uniqueness: {
    scope: :parent_id,
    conditions: -> { all.available },
    message: -> { I18n.t('mongoid.errors.models.actor.attributes.name.uniqueness') },
    unless: ->(a) { a.deleted? || a.is_mapping? || a.is_user? }
  }

  with_options unless: :skip_all_callbacks? do
    before_create :before_create
    before_validation :before_validation
    before_save :before_save
    before_save :handle_soft_delete

    # This auto creates the default groups and assigns default roles
    # to these groups dependeing on actor type by the settings
    # coming from DEFAULTS
    after_save :ensure_defaults!
    after_save :rebuild_path!, if: -> { name_previously_changed? || deleted_previously_changed? }
    after_save :set_children_count!
    after_save :merge_group_candos!, if: :role_ids
  end

  # Strategy to handle deletion of a node with children
  before_destroy :before_destroy
  before_destroy :destroy_children, unless: :is_mapping?
  before_destroy :destroy_mappings, unless: :is_mapping?
  after_destroy :cache_expire!, unless: :is_mapping?
  def destroy_mappings
    mappings.destroy_all
  end

  index _type: 1, deleted: 1, map_actor_id: 1
  index deleted: 1, _id: 1
  index deleted: 1, name: 1, _type: 1, map_actor_id: 1

  index(
    {
      name: 1,
      path: 1
    },
    {
      unique: true,
      name: 'actor_path_unique_undeleted',
      partial_filter_expression: {
        deleted: false
      }
    }
  )

  index parent_id: 1, name: 1
  index parent_id: 1, user_id: 1, _keywords: 1
  index tenant_id: 1, parent_template_actor_id: 1, user_id: 1
  index parent_template_actor_id: 1, user_id: 1
  index user_id: 1
  index parent_ids: 1, _type: 1, deleted: 1
  # undefine redundant parent_ids index which comes as default from `include Mongoid::Tree`
  index_specifications.reject! {|idx| idx.key == { parent_ids: 1 } }

  index tenant_id: 1, cached_role_ids: 1
  index tenant_id: 1, cached_role_names: 1
  index tenant_id: 1, cached_candos: 1
  index parent_id: 1, parent_ids: 1, user_id: 1, friendlyname: 1, _id: 1

  index role_ids: 1

  # fields
  strip_attributes
  field :auto, type: Boolean, default: false
  field :deleted, type: Boolean, default: false
  field :deleted_at, type: Time
  field :active, type: Boolean, default: true
  field :name, type: String
  field :title, type: String, localize: true

  field :short_name, type: String # old
  field :full_name, type: String # old

  field :path_ids, type: String
  field :path, type: String
  field :write_protected, type: Boolean, default: false
  field :system, type: Boolean, default: false
  field :image_data, type: Hash # for shrine attachment
  field :children_count, type: Integer, default: 0
  field :actor_settings, type: Hash, default: {}

  def title=(t)
    _title = super
    self.title_translations = I18n.available_locales.collect do
      [it.to_s, title_translations.fetch(it.to_s, t)]
    end.to_h
    _title
  end

  def merge_group_candos!
    _mappings = Actors::Mapping.where(parent_ids: self.id)
    _mappings.merge_group_candos!
    ::User.where(:_id.in => _mappings.distinct(:user_id)).cache_expire!
  end

  def actor_type
    self._type.to_s.demodulize.underscore
  end

  def may_have_roles?
    return true if self.is_a? Actors::Group
    return true if self.is_a? Actors::Ou
    false
  end

  # default settings from yml
  def self.default_settings
    @@default_settings ||= YAML::load_file(::Rails.root.join('config', 'per_app_settings.yml'))
  end

  def proper_name
    unless get_name.to_s.to_slug.length >= 1
      errors.add(:name, I18n.t('errors.actor.name_is_invalid'))
    end
  end

  def uri
    return @uri=nil if url.blank?
    @uri ||= begin
      URI.parse(url)
    end
  end

  def host
    return @host=nil if uri.blank?
    @host ||= begin
      uri.host || uri.to_s
    end
  end

  # Helper to view the tree structure of an Actor node
  # mostly useful on a console. Usage example:
  #     Actors::App.im.visualize
  def visualize
    _children = self.children.available.where(:_type.nin => [Actors::Mapping, Actors::User]).collect(&:visualize)
    _roles = roles.pluck(:name).sort
    _node = { self._type => "#{path} (#{children.available.count})" }
    _node['roles'] = _roles.join(", ") if _roles.any?
    _node['children'] = _children if _children.any?
    _node
  end

  def get_app_orga(without: [])
    @get_app_orga = app.organization.descendants.available.includes(:roles).order(depth: 1, name: 1).collect do |node|
      _node = HashWithIndifferentAccess.new({
        _id: node.id,
        parent_id: node.parent_id,
        name: node.name,
        _type: node._type
      })
      _node[:template_actor_id] = node.id unless without.include?(:template_actor_id)
      _node[:title_translations] = node.title_translations unless without.include?(:title_translations)
      _node.merge!(roles: node.roles.pluck(:name)) unless without.include?(:roles)
      _node
    end
    treeify @get_app_orga
  end

  def treeify(arr)
    nested_hash = arr.map{|a| [a[:_id], a.merge(children: [])]}.to_h
    nested_hash.each do |id, item|
      parent = nested_hash[item[:parent_id]]
      if parent
        parent[:children] << item.slice(:name, :_type, :template_actor_id, :title_translations, :roles)
        nested_hash.delete id # remove what was sorted
      end
    end.values.collect do |item|
      item.delete :_id
      item.delete :parent_id
      item
    end
  end

  def get_tree(without: [])
    _children = self.children.available.collect{|c| c.get_tree(without: without) }
    _node = HashWithIndifferentAccess.new({
      name: self.name,
      _type: self._type
    })
    _node[:template_actor_id] = self.id unless without.include?(:template_actor_id)
    _node[:title_translations] = self.title_translations unless without.include?(:title_translations)
    _node[:roles] = self.roles.pluck(:name) unless without.include?(:roles)
    _node[:children] = _children if _children.any?
    _node
  end

  def settings
    @settings ||= begin
      _settings = actor_settings.to_h.deep_symbolize_keys
      if is_app?
        _settings[:url] ||= self.config.url
        _uri = URI.parse(_settings[:url] || 'https://domain.local')
        _settings[:bearer_token] = !!self.config.bearer_token
        _settings[:mailer] ||= self.config.mailer.attributes.except(:_id)
        _settings[:redirects] ||= self.class.default_settings.deep_symbolize_keys.dig(:default_redirects)
        _settings[:redirects][:authenticated].gsub!(/\/authenticated#/, '/authenticated?') unless _settings[:bearer_token].eql?(true)
        _settings
      end
    end
  end

  validates :name, presence: true
  validates :title, presence: true, if: ->() {
    return true if self.is_a?(Actors::Ou)
    return true if self.is_a?(Actors::Group)
    false
  }
  def validate_presence_for_languages
    return [] if self.is_a?(Actors::Mapping)
    return [] if self.is_a?(Actors::Tenant)
    return [] unless app.is_a?(Actors::App)
    [app.default_language].compact
  end

  def before_destroy
    record = self
    if record.system && !record.system_override
      errors.add :system, 'protection flag set'
      throw(:abort)
    end
  end

  def ensure_required_fields
    @ensure_required_fields ||= begin
      record = self
      if record.name_changed? || record.short_name_changed?
        record.name = record.get_name
      end
      record.path ||= record.send(:determine_path)  # trigger path init if not set
      record.full_name = nil if record.full_name.blank?
      record.short_name = nil if record.short_name.blank?
      record.title = nil if record.title.blank?
      record.full_name ||= record.short_name ||= record.title ||= record.name
      record._keywords = record.get_index_keywords
      true
    end
  end

  def before_create
    ensure_required_fields
  end

  def before_validation
    ensure_required_fields
  end

  def before_save
    record = self
    record.role_ids = record.role_ids.uniq.sort if record.role_ids.is_a?(Array)

    record.ensure_required_fields

    if record.write_protected && record.write_protected_was && !record.system_override
      errors.add :write_protected, 'protection flag set'
      throw(:abort)
    end
    if record.system && record.deleted && !record.system_override
      errors.add :system, 'protection flag set'
      throw(:abort)
    end
    if record.is_user? && !record.parent.eql?(Actor.user_container)
      errors.add :parent_id, I18n.t('mongoid.errors.models.actor.attributes.parent_id.invalid')
      throw(:abort)
    end

    # ensure mappings are deleted
    if record.is_mapping? && record.deleted?
      record.delete
      throw(:abort)
    end

    # sync deleted to mappings
    if record.deleted_changed? && record.persisted?
      if record.is_user?
        u = User.where(actor: record).first
        u.set(deleted: record.deleted?) unless u.nil?
      end
       # adds uuid after the name so the account can be re-created
      record.name_uniquely_disabled! if record.deleted?
      record.mappings.set(deleted: record.deleted?)
      record.descendants.set(deleted: record.deleted?)
    end
    (record.image_derivatives! rescue nil) if record.image
  end

  def handle_soft_delete
    if deleted?
      deleted_at ||= Time.now
    else
      deleted_at = nil
    end
  end

  def new_user=(u)
    @new_user = u
  end
  def new_user
    @new_user || user
  end

  # Name is the main ident and unique within a tree node
  # For Users or mappings of one this should be the email address
  # otherwise a slug-conversion of short_name
  def get_name
    #@get_name = nil unless self.persisted? # don't cache it when we're creating the record, otherwise this will have side effects
    return @get_name = self.name.to_s.to_slug if self.deleted?
    @get_name ||= begin
      if self.deleted?
        self.name
      elsif self.new_user.is_a?(User)
        self.new_user.email.downcase
      elsif self.is_mapping? && self.map_actor && self.map_actor.is_user? && self.map_actor.user.is_a?(User)
        self.map_actor.user.email.downcase
      elsif self.is_user? && self.user.is_a?(User)
        self.user.email.downcase
      elsif self.name.blank? && self.short_name.blank? && self.title.present?
         self.title.to_s.to_slug
      else
        if self.short_name.blank?
          self.name.to_s.to_slug
        else
          self.short_name.to_s.to_slug
        end
      end
    end
    @get_name
  end

  def name_uniquely_disabled!
    self.name = self.short_name = "#{self.name.split('---')[0,1].join('---')}---#{self.id}"
    debug_puts "name_uniquely_disabled! #{self.name}"
    true
  end

  def determine_path
    @determine_path ||= begin
      debug_puts "=" * 80
      debug_puts "determine_path #{self.path} #{self.id}"
      debug_puts "=" * 80
      base_path = []
      if parent.present?
        base_path << self.parent.path
      end
      _name = self.name = self.get_name
      base_path << _name
      base_path * ' / '
    end
  end

  def skip_callbacks
    @skip_callbacks || false
  end
  def skip_callbacks=(_status)
    @skip_callbacks = !!_status
  end

  def self.path(p)
    where(path:p).first
  end

  def self.writable
    criteria.where(write_protected: { '$ne': true })
  end
  def self.deletable
    criteria.where(system: { '$ne': true })
  end

  # filter for only structural actor types
  def self.tree_nodes
    available.where(:_type.nin => [Actors::User, Actors::Mapping])
  end

  def self.users
    reorder(nil).where(_type: Actors::User)
  end
  def self.mappings
    criteria.reorder(nil).where(_type: Actors::Mapping)
  end
  def self.mappings_and_users
    reorder(nil).where(:_type.in => [Actors::Mapping, Actors::User])
  end
  def self.containers
    reorder(nil).where(_type: /^Actors::Container/)
  end
  def self.apps
    reorder(nil).where(_type: Actors::App)
  end
  def self.tenants
    reorder(nil).where(_type: Actors::Tenant)
  end
  def self.ous
    reorder(nil).where(_type: Actors::Ou)
  end
  def self.groups
    reorder(nil).where(_type: Actors::Group)
  end
  def self.groups_and_ous
    reorder(nil).where(:_type.in => [Actors::Group, Actors::Ou])
  end

  def self.admin
    Actor.users.where(name: 'Admin').first_or_create(
      system: true,
      write_protected: true,
      parent: user_container,
      auto: true,
      short_name: 'Admin',
      full_name: 'Administrator',
      title: 'Administrator'
    )
  end

  def self.get_mappings(actor, mapped)
    case mapped.to_i
    when 0
      user_container.children.available
    when 1
      actor.children.mappings.available
    else
      user_container.children.available.where(:id.nin => actor.children.mappings.pluck(:map_actor_id))
    end
  end

  # The container that holds all users. Creates the actor if it doesn't exist.
  # @return {Actor}
  def self.user_container
    @@user_container ||= Actors::ContainerUsers.where(parent: nil).first_or_create(name: :users, system: true, write_protected: true)
  end
  # The container that holds all apps. Creates the actor if it doesn't exist.
  # @return {Actor}
  def self.app_container
    @@app_container ||= Actors::ContainerApps.where(parent: nil).first_or_create(name: :apps, system: true, write_protected: true)
  end

  # @return {Array} of {Hash}es with id, name fields and candos for the given user
  def self.tenant_collection(user)
    criteria.collect do |t|
      {
        id: t.id.to_s,
        name: t.name,
        short_name: t.short_name,
        full_name: t.full_name,
        title: t.title,
        enterprises: t.enterprises,
        candos: user.candos.dig(t.id.to_s),
        image: {
          large: (t.image[:large].url rescue nil),
          medium: (t.image[:medium].url rescue nil),
          small: (t.image[:small].url rescue nil)
        }
      }
    end
  end

  # Optional: on creation provides this actor
  # with special privileges (e.g. on creating a tenant
  # this actor will become member of all default groups)
  def owner=(a)
    @owner = a
  end
  def owner
    @owner
  end

  # # virtual attribute to signal
  # # if this node is selectable in a picker context
  # def selectable
  #   @selectable ||= false
  # end
  # def selectable=(v)
  #   @selectable = !!v
  # end
  # virtual attribute to signal
  # if this node is already mapped in a picker context
  def mapped
    @mapped ||= false
  end
  def mapped=(v)
    @mapped = !!v
  end

  # for frontend ruleset only
  # is not enforced on server side!
  def insertable_child_types
    case actor_type.to_sym
    when :user
      []
    when :container_users
      []
    when :container_apps
      [] # apps are not to be created via UI! #156
    when :container_enterprises
      %i[enterprise]
    when :container_tenants
      %i[tenant]
    when :app, :tenant
      %i[group ou]
    when :group
      []
    when :enterprise
      %i[mapping]
    when :ou
      %i[ou group]
    else
      []
    end
  end

  def self.system_override
    @@system_override ||= false
  end
  def self.system_override=(v)
    @@system_override = !!v
  end
  def system_override
    @system_override ||= @@system_override ||= false
  end
  def system_override=(v)
    @system_override = !!v
  end

  # # translatable actor attributes
  # def short_name
  #   return super unless self.system?
  #   translate_me(__method__, super)
  # end
  # def full_name
  #   return self.path if self.is_mapping?
  #   return super unless self.system?
  #   translate_me(__method__, super)
  # end
  def name
    super || (self.short_name.to_slug rescue nil)
  end

  def image_b64=(b64_encoded)
    return if b64_encoded.blank?
    self.image = Base64StringIO.from_base64(b64_encoded)
  end

  def image=(file_data)
    return if file_data.blank?
    return super file_data unless file_data.is_a?(String)
    super Base64StringIO.from_base64(file_data)
  end

  # Expire cached data on users (candos and tenants)
  def cache_expire!
    if self.is_mapping?
      ::User.where(actor_id: map_actor_id).cache_expire!
    else
      _actor_ids = Actors::Mapping.where(parent_ids: self.id).distinct(:map_actor_id)
      ::User.where(:actor_id.in => _actor_ids).cache_expire! if _actor_ids.any?
    end
  end

  # Convenience helper
  # @return {Boolean} indicating if this actor is a user
  def is_user?
    self._type.eql?('Actors::User')
  end
  # Convenience helper
  # @return {Boolean} indicating if this actor is a tenant
  def is_tenant?
    self._type.eql?('Actors::Tenant')
  end
  # Convenience helper
  # @return {Boolean} indicating if this actor is an app
  def is_app?
    self._type.eql?('Actors::App')
  end
  # Convenience helper
  # @return {Boolean} indicating if this actor is a group
  def is_group?
    self._type.eql?('Actors::Group')
  end
  # Convenience helper
  # @return {Boolean} indicating if this actor is a OU
  def is_ou?
    self._type.eql?('Actors::Ou')
  end
  # Convenience helper
  # @return {Boolean} indicating if this actor is a container
  def is_container?
    self._type.to_s =~ /^Actors::Container/ ? true : false
  end
  # Convenience helper
  # @return {Boolean} indicating if this actor is a container
  def is_mapping?
    self._type.eql?('Actors::Mapping')
  end

  def actors
    @actors ||= self.determine_actors
  end

  # Determine all actorss of all inherited ancestors
  def determine_actors
    @actors = Actor.where(:id.in => self.determine_actor_ids)
  end

  def actor_ids
    @actor_ids ||= self.determine_actor_ids.to_a
  end

  def global_role_ids(tenant_id: nil)
    @global_role_ids ||= Actor.where(:id.in => determine_actor_ids).pluck(:role_ids).flatten.compact.uniq
  end

  def global_functionality_ids(tenant_id: nil)
    @global_functionality_ids ||= Role.available.where(:_id.in => global_role_ids).pluck(:functionality_ids).flatten.compact.uniq
  end

  # Determine all actor IDs of all inherited ancestors
  def determine_actor_ids
    _ancestors_and_self_ids = [self.id]+self.ancestors.available.distinct(:_id)
    _ancestors_and_self_ids + 
    Actor.collection.aggregate(self.aggregation_recursive_actor_mapping_lookup).pluck(:_id) +
    @actor_ids = Actor.available.mappings.where(:map_actor_id.in => _ancestors_and_self_ids).distinct(:parent_ids)
  end

  def redetermine_actor_ids
    # helper to clean cached actor ids
    @actor_ids = nil
  end

  def functionality_ids
    @functionality_ids ||= self.determine_functionality_ids
  end

  # Determine all functionality_ids of all inherited ancestors
  def determine_functionality_ids
    @functionality_ids = self.roles.pluck(:functionality_ids).flatten.compact.uniq.sort
  end

  # Determine candos for all functionalities in the actor's roles
  def determine_candos
    determine_functionalities.collect(&:cando).sort
  end

  def functionalities
    @functionalities ||= self.determine_functionalities
  end

  # Determine all functionalities of all inherited ancestors
  def determine_functionalities
    @functionalities = Functionality.where(:_id.in => determine_functionality_ids)
  end

  # Helper to recursively determine mappings up to 10 nested levels of
  # mappings where any parent/ancestor maybe be mapped anywhere again.
  # @param actor {Actor} The actor to resolve
  # @return {Array} aggregation options
  def self.aggregation_recursive_actor_mapping_lookup(actor)
    [{
      '$match' => { # start by locating mapped actors of the given actors ancestral path
        '_type' => 'Actors::Mapping',
        'map_actor_id' => {
          '$in' => [actor.id] + actor.ancestors.pluck(:_id)
        }
      }
    }, {
      '$graphLookup' => { # recursively find nested actor mappings
        'from' => 'actors',
        'startWith' => '$parent_ids',
        'connectFromField' => 'parent_ids',
        'connectToField' => 'map_actor_id',
        'as' => '_mapped_actors', # resulting in memory field {Array} of :mapping type Actors
        'maxDepth' => 10, # maximum levels of nesting (4 is plenty - 10 is generous)
        'restrictSearchWithMatch' => {
          '_type' => 'Actors::Mapping' # speeds things up
        }
      }
    }, {
      '$unwind' => { # turn the result in a simpler format
        path: '$_mapped_actors',
        preserveNullAndEmptyArrays: false
      }
    }, {
      '$group' => { # works like distinct to get rid of duplicates
        _id: '$_mapped_actors.parent_id'
      }
    }]
  end

  # Helper that determines nested actor inheritance
  def aggregation_recursive_actor_mapping_lookup
    self.class.aggregation_recursive_actor_mapping_lookup(self)
  end

  # Maps the given actor into #self (normally self being _type Actors::Group)
  # @param actor {Actor} the actor that will become member of this instance
  # @param attrs {Hash} optional attributes to set on this actor
  def map_into!(actor, attrs={}, cache_expire: true)
    user = actor if actor.is_a?(::User)
    actor = actor.actor if actor.is_a?(::User)
    user ||= actor.user if actor.is_a?(Actors::User)
    raise "Can only map actors!" unless actor.is_a?(Actor)
    raise "Can only map persisted actors!" if actor.new_record?


    # mapped_actor = self.children.mappings.where(map_actor: actor).first_or_initialize()
    mapped_actor = Actors::Mapping.where(parent: self, map_actor: actor).first_or_initialize(user_id: user&.id)
    return mapped_actor if mapped_actor.persisted?
    mapped_actor.attributes = attrs.merge({
      deleted: false,
      active: actor.active,
      name: actor.get_name,
      title: actor.short_name,
      short_name: actor.short_name,
      full_name: "#{self.path}/@#{actor.name}"
    })
    if mapped_actor.changed?
      mapped_actor.save!
    else
      mapped_actor.ensure_user_data
      mapped_actor.ensure_references
      mapped_actor.user_cache_expire!
      mapped_actor.merge_group_candos!
    end

    if cache_expire
      actor.cache_expire!
    end
    actor.redetermine_actor_ids # actor ids changed, force redetermination
    mapped_actor
  end

  # removes mapping of given actor from #self
  def unmap_from!(actor, cache_expire: true)
    actor = actor.actor if actor.is_a?(User)
    raise "Can only unmap actors!" unless actor.is_a?(Actor)
    mapped_actor = Actors::Mapping.where(parent: self, map_actor: actor).first
    if mapped_actor.is_a?(Actor)
      mapped_actor.cache_expire! if cache_expire
      mapped_actor.delete
      actor.cache_expire! if cache_expire
      actor.redetermine_actor_ids # actor ids changed, force redetermination
      true
    else
      false
    end
  end

  def defaults
    self.class::DEFAULTS[self._type.to_sym] rescue nil
  end

  def get_app_name
    return self.name if self.is_a?(Actors::App)
    self.path.split('/').second.strip
  end

  def ensure_defaults!(with_defaults: nil, cache_expire: true)
    return if deleted?
    return if is_mapping?
    @ensure_defaults ||= begin

      debug_puts "\n" * 5
      debug_puts "=" * 80
      debug_puts "ensuring defaults for: #{self.path} of #{self.class} are"
      debug_puts "=" * 80
      debug_puts "\n" * 2

      _defaults = with_defaults || self.defaults
      if _defaults.is_a?(Hash)
        debug_puts "-"*80
        debug_puts "defaults #{self.path} of #{self.class} are"
        debug_ap _defaults
        debug_puts "-"*80
        begin
          # disable costly callbacks until we're done
          _roles = _defaults[:roles]
          if _roles.is_a?(Array) && self.get_app_name.present?
            # expand ~ prefix to name so "~-app-admin" becomes "somename-app-admin"
            _roles = _roles.collect {|r| r.gsub(/^\~/, self.get_app_name) }
          end
          if _roles.present?
            # ensure default roles
            debug_puts "-"*80
            debug_puts " to actor: #{self.id} / #{self.name}"
            debug_puts "   - adding roles #{_roles.present? ? _roles : 'NONE'}"
            ensure_named_roles(_roles)
            debug_puts "   - adding roles DONE!"
            debug_puts "-"*80
          end
          # ensure default groups
          return unless _defaults[:children] && _defaults[:children].try(:any?)
          recursion_defaults(self, _defaults[:children], cache_expire: false)
        ensure
          # re-instate callbacks previously disabled
          debug_puts "=" * 80
          debug_puts "finalizing #{self.path} with child counter updates..."
          debug_puts "=" * 80
          #set_children_count!
        end
      end
      self.cache_expire! if cache_expire
      true
    end
  end

  def ensure_named_roles(role_names)
    @@role_cache ||= {}
    unless (role_names - @@role_cache.keys).empty?
      Role.where(:name.in => role_names).each do |r|
        @@role_cache[r.name] ||= r.id
      end
    end
    _role_ids = role_names.collect {|rn| @@role_cache.dig(rn) }
    self.role_ids = [self.role_ids, _role_ids].flatten.compact.uniq.sort
  end

  def recursion_defaults(base_actor, children, cache_expire: false)
    _children_defaults = (children||[])
    (_children_defaults).each do |_child|
      _child[:_type] ||= Actors::Group.to_s
      debug_puts "base_actor: #{base_actor.path} // _child: #{_child}"
      begin
        if _child[:email].present? && base_actor.is_group?
          # allows auto mapping users into groups
          _user = User.available.email(_child[:email])
          if _user.present?
            base_actor.map_into!(_user, cache_expire: false)
          end
        else
          _actor = _child[:_type].constantize.where(
            parent: base_actor,
            name: _child[:name]
          ).first_or_initialize
          # allow soft defaults in yml with `system: false` - defaults to true
          _system = _child[:system].eql?(false) ? false : true

          _actor.attributes = {
            system: _system,
            template_actor_id: (BSON::ObjectId(_child[:template_actor_id]) rescue nil)
          }
          if _child[:title_translations].is_a?(Hash)
            _actor.title_translations = _child[:title_translations]
          end
          _actor.skip_all_callbacks!
          _actor.ensure_required_fields
          _actor.owner = owner

          # add roles
          _roles = _child[:roles]
          if _roles.is_a?(Array) && self.get_app_name.present?
            # expand ~ prefix to name so "~-app-admin" becomes "somename-app-admin"
            _roles = _roles.collect {|r| r.gsub(/^\~/, self.get_app_name) }
          end
          debug_puts "-"*80
          debug_puts " to actor: #{_actor.id} / #{_actor.name}"
          debug_puts "   - adding roles #{_roles.present? ? _roles : 'NONE'}"
          debug_puts "-"*80
          _actor.ensure_named_roles(_roles) if _roles.present?
          _actor.save if _actor.changed? #validate: false
          debug_puts "   - adding roles done!"
          # This ensures the "owner" of a tenant get's access everywhere
          if owner.is_a?(Actor) && _actor.is_group?
            debug_puts "   - mapping owner..."
            _actor.map_into!(owner, cache_expire: false)
          end
          debug_puts "SUB ensure_defaults on #{_actor.path} - #{_actor.class}..."
          _actor.ensure_defaults! cache_expire: false
          next unless _actor.depth < 7 # prevent overly complex structures
          if _child[:children].is_a?(Array) && _child[:children].try(:any?)
            recursion_defaults _actor, _child[:children], cache_expire: cache_expire
          end
        end
        base_actor.set_children_count!
      end
    end
  end

  def self.create_defaults!
    # Create roles with their basic functionalities via db/seeds.rb
    Rails.application.load_seed
  end

  def get_index_keywords
    self.class.get_index_keywords(path)
  end

  # Shortcut to turn text into an Array of keywords
  def self.get_index_keywords(text)
    Mongoid::Search::Util.normalize_keywords text
  end

  # Virtual attribute to set in user/app_controller to signal
  # if outstanding acceptances for Content exists
  def requires_acceptance
    @requires_acceptance ||= false
  end
  def requires_acceptance=(v)
    @requires_acceptance = v #? true : false
  end

  def set_children_count!
    debug_puts "SETTING CHILDREN COUNT: #{self.path}"
    debug_puts "-" * 80
    _children_count = is_mapping? ? 0 :self.children.tree_nodes.count
    return if self.children_count == _children_count # nothing to do
    set(children_count: _children_count)
    debug_puts "done setting _children_count of #{_children_count} on #{self.path}"
    nil
  end

  def tenant
    @tenant ||= begin
      if is_tenant?
        self
      else
        ancestors.where(_type: Actors::Tenant).first
      end
    end
  end

  def app
    @app ||= begin
      if is_app?
        self
      else
        ancestors.find_by(_type: Actors::App) rescue nil
      end
    end
  end

  # Update path in tree for user readable output and reloads to reflect the updated path
  # @return {String} Dash separated path in the actor tree
  def rebuild_path!
    return if new_record?

    self.class.where('$or': [{ _id: id }, { parent_ids: id }]).merge_rebuild_path!
    _latest = self.class.where(_id: id).only(:path).first
    attributes['path'] = _latest.path
  end

  def self.aggregation_rebuild_path
    [
      {
        '$match' => criteria.selector
      }
    ] + [
      {
        '$project': {
          'parent_ids': 1, 
          'name': 1
        }
      }, {
        '$addFields': {
          'path_ids': {
            '$concatArrays': [
              {
                '$ifNull': [
                  '$parent_ids', []
                ]
              }, [
                '$_id'
              ]
            ]
          }
        }
      }, {
        '$lookup': {
          'from': 'actors', 
          'localField': 'path_ids', 
          'foreignField': '_id', 
          'as': 'parents', 
          'pipeline': [
            {
              '$project': {
                'name': 1
              }
            }
          ]
        }
      }, {
        '$unwind': '$path_ids'
      }, {
        '$unwind': '$parents'
      }, {
        '$match': {
          '$expr': {
            '$eq': [
              '$path_ids', '$parents._id'
            ]
          }
        }
      }, {
        '$group': {
          '_id': '$_id', 
          'parent_ids': {
            '$first': '$parent_ids'
          }, 
          'name': {
            '$first': '$name'
          }, 
          'path_ids': {
            '$push': '$path_ids'
          }, 
          'parents': {
            '$push': '$parents'
          }, 
          'parent_names': {
            '$push': '$parents.name'
          }
        }
      }, {
        '$addFields': {
          'path': {
            '$reduce': {
              'input': '$parent_names', 
              'initialValue': '', 
              'in': {
                '$concat': [
                  '$$value', {
                    '$cond': [
                      {
                        '$eq': [
                          '$$value', ''
                        ]
                      }, '', ' / '
                    ]
                  }, '$$this'
                ]
              }
            }
          }
        }
      }, {
        '$project': {
          'path': 1
        }
      }
    ]
  end

  def self.merge_rebuild_path!
    collection.aggregate(
      aggregation_rebuild_path +
      [
        {
          '$merge' => {
            'into' => 'actors',
            'on' => '_id',
            'whenMatched' => 'merge',
            'whenNotMatched' => 'discard'
          }
        }
      ]
    ).to_a
  end

  # fetches the next available uniq name with criteria
  def self.name_uniq(n)
    _name = n.downcase
    _rx = Regexp.new("^#{_name}(?:-)?(?<num>\\d*)?$", Regexp::IGNORECASE)

    # aggregate names from db matching the name with optional number after dash
    # returns the highest number variant or
    _aggregration = collection.aggregate(
      [
        { "$match": criteria.selector },
        {
          '$match': {
            'name': _rx
          }
        }, {
          '$project': {
            'name': 1, 
            'name_length': {
              '$strLenCP': '$name'
            }
          }
        }, {
          '$sort': {
            'name_length': -1,
            'name': -1
          }
        }, {
          '$limit': 1
        }, {
          '$project': {
            'name': 1
          }
        }
      ]
    )
    _existing_name = _aggregration.first.try(:dig, :name)
    # name doesn't exist yet
    return _name unless _existing_name.present?

    _match = _rx.match(_existing_name)
    "#{_name}-#{_match[:num].to_i+1}"
  end

end


# Notes
## Mongoid::Tree
# Node.root
# Node.roots
# Node.leaves
# --
# node.root
# node.parent
# node.children
# node.ancestors
# node.ancestors_and_self
# node.descendants
# node.descendants_and_self
# node.siblings
# node.siblings_and_self
# node.leaves
# --
# node.root?
# node.leaf?
# node.depth
# node.ancestor_of?(other)
# node.descendant_of?(other)
# node.sibling_of?(other)
# --
# node.lower_siblings
# node.higher_siblings
# node.first_sibling_in_list
# node.last_sibling_in_list
# --
# node.move_up
# node.move_down
# node.move_to_top
# node.move_to_bottom
# node.move_above(other)
# node.move_below(other)
# --
# node.at_top?
# node.at_bottom?
