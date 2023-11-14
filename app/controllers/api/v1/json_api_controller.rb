class Api::V1::JsonApiController < ApplicationController
  wrap_parameters false

  delegate :url_helpers, to: 'Rails.application.routes'

  before_action :default_format_json
  before_action :authenticate_user! # use devise based token auth
  before_action :authorize
  before_action :request_variant

  JSON_API = true

  MODEL_BASE = nil
  MODEL_BASE_ACTION = {}
  MODEL = nil
  MODEL_OVERVIEW = nil
  SERIALIZER = nil
  OVERVIEW_SERIALIZER = nil
  SCHEMA_ACTION = {}

  PAGE_LIMIT = 50
  PAGE_LIMIT_MAX = 100

  PERMIT_CREATE = []
  PERMIT_UPDATE = []

  SWAGGER = {}

  GIT_VERSION = File.read("public/version.txt").strip rescue "UNKNOWN"

  CANDO = {
   #all: %w(public) # @DEV ONLY !!! DISABLES USER AUTHORIZATION
  }

  def index(&block)
    respond_to do |format|
      format.xlsx {
        render plain: nil, status: 404 and return unless model_index.xlsx_allowed?
        download = Download.create(
          user_id: current_user.try(:id),
          name: "#{[model_index.model_name.human(count:2), Time.now.strftime('%Y%m%d-%H%M%S')].reject(&:blank?).join('-')}.xlsx",
          file: records_index_sorted.as_xlsx(params_json_api).to_stream
        )
        render_jsonapi_msg({
          name: download.name,
          url: download.file.url
        })
      }
      format.any {
        render_serialized_records(
          records: records_index_paged_to_a,
          total: records_index.count
        ) do |records, opts|
          records, opts = yield(records, opts) if block_given?
          [records, opts]
        end
      }
    end
  end

  def show(&block)
    record = record_show

    respond_to do |format|
      format.pdf do |variant|
        render plain: nil, status: 404 and return unless record.respond_to?(:as_pdf)

        variant.header  { render html: record._pdf_header and return }
        variant.content { render html: record._pdf_content and return }
        variant.footer  { render html: record._pdf_footer and return }
        variant.preview { render html: record._pdf_preview and return }

        variant.download { render plain: record.as_pdf(*record_show_as_pdf_params).to_s, content_type: 'application/pdf' and return }

        variant.none {
          download = Download.create(
            user_id: current_user.try(:id),
            name: record.filename(:pdf),
            file: StringIO.new(record.as_pdf)
          )
          render_jsonapi_msg({
            name: download.name,
            url: download.file.url
          })
        }
      end

      format.json {
        render_serialized_record(
          record: record
        ) do |record, opts|
          record, opts = yield(record, opts) if block_given?
          [record, opts]
        end
      }
    end
  end

  def create(&block)
    # we need to be overly specific here to handle the fact that
    # when uniqueness of field is additionally enforced via a mongodb unique index
    # we won't get to see the ActiveModel errors from validations but a hard fail
    # with a useless generic mongodb error only
    record = record_create
    record.attributes = params_create
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record(
      record: record
    ) do |record, opts|
      record, opts = yield(record, opts) if block_given?
      [record, opts]
    end
  end

  def update(&block)
    record = record_update
    record.attributes = params_update
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record(
        record: record
    ) do |record, opts|
      record, opts = yield(record, opts) if block_given?
      [record, opts]
    end
  end

  def destroy
    records = records_destroy
    undeletables = []
    records.to_a.each do |record|
      if record.respond_to?(:deleted)
        record.deleted = true
        record.save(validate: false)
      else
        record.destroy
        undeletables << record if record.errors.any?
      end
    end
    render_jsonapi_msg({
      success: undeletables.empty?,
      error: (undeletables.empty? ? nil : :conflict),
      message: I18n.t('errors.undeletable', count: undeletables.length, total: records.to_a.length),
      error_details: (undeletables.empty? ? nil : undeletables.inject({}) do |hsh, record|
        hsh[record.id] = record.errors.to_a
        hsh
      end)
    }, (undeletables.empty? ? 200 : 409))
  end

  # helper to use permitted param names from Controller constant
  # both in the permitted params as well as in api specs
  def self.permitted_attributes_for_update
    begin
      raise "No attributes permitted in #{self.class}::PERMIT_UPDATE" unless self::PERMIT_UPDATE.any? rescue false
      self::PERMIT_UPDATE.collect do |_name|
        _name.is_a?(Hash) ? _name.keys : _name
      end.flatten
    end
  end

  # helper to use permitted param names from Controller constant
  # both in the permitted params as well as in api specs
  def self.permitted_attributes_for_create
    begin
      raise "No attributes permitted in #{self.class}::PERMIT_CREATE" unless self::PERMIT_CREATE.any? rescue false
      self::PERMIT_CREATE.collect do |_name|
        _name.is_a?(Hash) ? _name.keys : _name
      end.flatten
    end
  end

  private
  def params_update
    params.fetch(:data, {}).permit(*self.class::PERMIT_UPDATE)
  end
  def params_create
    params.fetch(:data, {}).permit(*self.class::PERMIT_CREATE)
  end

  def request_variant
    request.variant = :header if params[:debug].to_s.eql?('header')
    request.variant = :content if params[:debug].to_s.eql?('content')
    request.variant = :footer if params[:debug].to_s.eql?('footer')
    request.variant = :download if params[:debug].to_s.eql?('download')
    request.variant = :preview if params[:debug].to_s.eql?('preview')
  end

  def model_index
    return self.class::MODEL_OVERVIEW unless self.class::MODEL_OVERVIEW.is_a?(Proc)
    instance_exec(&self.class::MODEL_OVERVIEW.to_proc)
  end
  def model_show
    return self.class::MODEL unless self.class::MODEL.is_a?(Proc)
    instance_exec(&self.class::MODEL.to_proc)
  end
  def model_create
    return self.class::MODEL unless self.class::MODEL.is_a?(Proc)
    instance_exec(&self.class::MODEL.to_proc)
  end
  def model_update
    return self.class::MODEL unless self.class::MODEL.is_a?(Proc)
    instance_exec(&self.class::MODEL.to_proc)
  end
  def model_destroy
    return self.class::MODEL unless self.class::MODEL.is_a?(Proc)
    instance_exec(&self.class::MODEL.to_proc)
  end

  def records_index
    @records_index ||= begin
      model_index.quickfilter(params_json_api[:quickfilter]||params_json_api[:query])
                 .gridfilter(params_json_api[:gridfilter])
                 .auto_includes(json_api_options[:include], overview_serializer)
    end
  end

  def records_index_sorted
    @records_index_sorted ||= begin
      records_index.sorting(params_json_api[:sort])
    end
  end

  def records_index_paged
    @records_index_paged ||= begin
      records_index_sorted
        .paginate(per_page: json_api_options[:limit], page: json_api_options[:page], padding: json_api_options[:padding])
    end
  end
  def records_index_paged_to_a
     @records_index_paged_to_a ||= records_index_paged.to_a
  end

  def record_show
    model_show.find(params_json_api[:id])
  end

  def record_create
    model_create.new(params_create)
  end

  def record_update
    model_update.find(params_json_api[:id])
  end

  def record_destroy
    model_destroy.find(params_json_api[:id])
  end
  def records_destroy
    ids = params_json_api[:id].to_s.gsub(',',' ').split(' ')
    model_destroy.find(ids)
  end

  def serializer
    self.class::SERIALIZER
  end
  def overview_serializer
    self.class::OVERVIEW_SERIALIZER
  end

  def render_serialized_records(records: nil, total: 0, meta: {}, status: 200, use_serializer: overview_serializer, &block)
    opts = {
      params: serializer_params,
      meta: serializer_meta.merge({
        total: total,
        msg: {
          success: true,
          error: nil
        }
      }).merge(meta||{}),
      is_collection: true,
      include: json_api_options[:include],
      fields:  json_api_options[:fields]
    }
    records, opts = block.call(records, opts) if block_given?
    render status: status, json: use_serializer.new(records, opts).serializable_hash
  end

  def render_serialized_record(record: nil, success: true, error: nil, meta: {}, use_serializer: serializer, &block)
    _meta = serializer_meta.merge({
      msg: {
        success: success,
        error: error
      }
    }).merge(meta||{})
    _meta[:json_api_options] = _meta[:json_api_options].except(:page, :limit)
    opts = {
      params: serializer_params,
      meta: _meta,
      is_collection: false,
      include: json_api_options[:include],
      fields:  json_api_options[:fields]
    }
    record, opts = block.call(record, opts) if block_given?
    status ||= (success ? 200 : 400)
    render status: status, json: use_serializer.new(record, opts).serializable_hash
  end

  def serializer_params
    { tenant_id: current_tenant_id, current_user: current_user, current_app_actor: current_app_actor, current_token: current_token, params_json_api: params_json_api }
  end

  def serializer_meta
    { yjit: (RubyVM::YJIT.enabled? rescue false), git_version: GIT_VERSION, json_api_options: json_api_options, locale: I18n.locale }
  end

  def json_api_permits
    [
      :app,
      :id, :ids, { ids: {} },
      :format, :debug, :locale, :bearer, 
      { export: {} }, 
      { data: {} }, 
      :name, :app, :tenant_id, 
      :quickfilter, :query, :per_page, :page, :padding, { page: {} }, { sort: {} }, :sort,
      { filter: {} }, :gridfilter, { gridfilter: {} },
      :include, fields: {}
    ]
  end

  def params_json_api
    params.permit(*json_api_permits)
  end

  def json_api_options
    @json_api_options ||= {
      limit: page_limit,
      page: page_number,
      padding: page_padding,
      include: (params_json_api[:include].split(',').collect(&:strip).collect(&:to_sym) rescue nil) || [],
      fields: sparse_fields
    }
  end

  def sparse_fields
    fields = params_json_api[:fields].to_h
    return [] unless fields.is_a?(Hash)
    fields.each {|field,v|fields[field.to_sym] = v.split(',').collect(&:strip).collect(&:to_sym) }
    fields
  end

  def page_limit
    @page_limit = params_json_api.dig(:page, :limit) rescue nil
    @page_limit ||= params_json_api[:per_page]
    @page_limit = @page_limit.numeric? ? @page_limit.to_i.abs : self.class::PAGE_LIMIT
    @page_limit = self.class::PAGE_LIMIT_MAX if @page_limit > self.class::PAGE_LIMIT_MAX
    @page_limit
  end

  def page_number
    @page_number = params_json_api.dig(:page, :number) rescue nil
    @page_number ||= params_json_api[:page]
    @page_number = @page_number.numeric? ? @page_number.to_i.abs : 1
    @page_number = 1 if @page_number < 1
    @page_number
  end

  def page_padding
    @page_padding = params_json_api.dig(:page, :padding) rescue nil
    @page_padding ||= params_json_api[:padding]
    @page_padding = @page_padding.numeric? ? @page_padding.to_i.abs : 0
    @page_padding
  end

  def check_for_errors(record)
    if record && !record.errors.empty?
      render_jsonapi_error(record.errors.full_messages.first, 'record_error', 400) and return
    end

    record
  end

  def authorize
    return if performed?
    return render_jsonapi_otp_required unless current_token.otp_satisfied?
    render_jsonapi_unauthorized unless authorization
  end

  def tenant_authorize
    return if performed?
    render_jsonapi_unauthorized unless tenant_authorization
  end

  def tenant_authorization
    return false unless current_cando_requirements.is_a?(Array)
    return true if current_action_is_public?
    if current_cando_requirements.any?
      return authorized_tenants.any? if current_action_is_multi_tenant?
      return (cando_any?(current_cando_requirements) rescue false)
    end
    false
  end

  def authorization
    _candos = current_cando_requirements
    return false unless _candos.is_a?(Array)
    return true if current_action_is_public?
    return (current_user.cando_any?(_candos) rescue false) if _candos.any?
    false
  end

  def current_cando_requirements
    @current_cando_requirements ||= begin
      requirements = [:all]
      requirements << "#{params[:action]}.*"
      if (params_json_api[:format] || 'json').eql?('json')
        # unsuffixed defaults to json format
        requirements << params[:action].to_sym
      else
        # a specific format is requested and requires explicit authorization
        requirements << "#{params[:action]}.#{params_json_api[:format]}".to_sym
      end
      _candos = get_candos.slice(*requirements).values
      _candos << [:unlimited]
    end
    @current_cando_requirements
  end

  def current_action_is_public?
    @current_action_is_public ||= current_cando_requirements.flatten.include?('public')
  end

  # multi_tenant candos don't require a tenant context
  # mainly intended for special api's that process data of many tenants
  def current_action_is_multi_tenant?
    @current_action_is_multi_tenant ||= current_cando_requirements.include?('multi_tenant')
  end

  # checks the cando requirements against all tenants the user is a member of
  # @return {Array} of tenants
  def authorized_tenants
    @authorized_tenants ||= (cando_any_for_tenants?(current_cando_requirements) rescue [])
  end

  # checks the cando requirements against all tenants the user is a member of
  # @return {Array} of tenant_ids
  def authorized_tenant_ids
    @authorized_tenant_ids ||= authorized_tenants.pluck(:id)
  end

  def cando_any_for_tenants?(of_these)
    current_user.tenants.select do |tenant|
      cando_any?(of_these, tenant)
    end
  end

  # Helper to compare required candos with those the current_user has
  def cando_any?(of_these, tenant=current_tenant)
    return false unless of_these.is_a?(Array)
    return false if of_these.empty?
    tenant_candos = (tenant ? tenant[:candos] : [])

    # handle combo cando requirements (2 or more candos joined by + sign)
    _of_these = of_these.collect{ |c| c.is_a?(String) ? c.split('+') : c }

    # of_these is a multi-level array
    # first level is the action or action.format that would grant access
    # second level is an array of possible cando combinations
    # the first combo (can be single entry) matching will grant access
    _of_these.each do |satisfying_actions|
      return false unless satisfying_actions.is_a?(Array)
      satisfying_actions.each do |cando_combo|
        return true if (tenant_candos & cando_combo).length.eql?(cando_combo.length)
      end
    end
    false
  end

  def current_tenant_id
    current_tenant[:id] rescue nil
  end

  def params_tenant_id
    params[:tenant_id] || nil
  end

  def current_tenant
    @current_tenant ||= current_user.tenants.find{|tenant| tenant[:id].to_s == params_tenant_id} rescue nil
  end

  def default_format_json
    request.format = "json" unless params_json_api[:format].present?
  end

  # handles the candos defined in each endpoint controller
  # each action can have an array of string candos (maybe + separated for combo candos)
  # or array of arrays with strings for combo cando requirements
  # e.g.
  #     # both variants require to have both the app-admin and example.writer cando
  #     show: %w(~/app.admin+some-app/example.writer)
  #     show: [['~/app.admin', 'some-app.example.writer']]
  def get_candos
    @get_candos ||= begin
      cando.merge({}).collect do |_action, _required_candos|
        _required_candos = _required_candos.collect do |c|
          _c = c.is_a?(String) ? c.split('+') : [c].flatten
          _c.collect do |s|
            s[0] = current_app_actor.name if s.start_with?('~/')
            s
          end
        end
        [_action, _required_candos]
      end.to_h
    end
  end

  def record_show_as_pdf_params
    {}
  end

  def default_format_json
    request.format = "json" unless params_json_api[:format].present?
  end

  if Rails.env.development? || Rails.env.local_dev?
    include DevelopmentJsonApiController
  end

end
