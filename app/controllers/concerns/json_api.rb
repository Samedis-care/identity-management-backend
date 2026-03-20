# Various helpers to use in controllers and rspec integration tests for rswag
# to consistently use the JSONAPI standard response object structures.
module JsonApi
  extend ActiveSupport::Concern
  require 'json/schema_builder'

  class StandardException < StandardError
    def initialize(msg, exception_type = 'standard_exception')
      @exception_type = exception_type
      super msg
    end
  end

  private
  def render_jsonapi_otp_required
    render_jsonapi_error(I18n.t('auth.error.otp_required'), 'otp_required', 401)
  end

  def render_jsonapi_unauthenticated
    render_jsonapi_error(I18n.t('auth.error.unauthenticated'), 'unauthenticated', 401)
  end

  def render_jsonapi_unauthorized
    render_jsonapi_error(I18n.t('auth.error.unauthorized'), 'unauthorized', 403)
  end

  def render_jsonapi_forbidden
    render_jsonapi_error(I18n.t('auth.error.forbidden'), 'forbidden', 403)
  end

  def render_jsonapi_unauthorized_tenant
    render_jsonapi_error(I18n.t('auth.error.unauthorized_tenant'), 'forbidden', 403)
  end

  def render_jsonapi_missing_tenant_context
    render_jsonapi_error(I18n.t('auth.error.missing_tenant_context'), 'missing_tenant_context', 400)
  end

  def render_jsonapi_error(message, error, status = 500, meta: {}, exception: nil)
    exception ||= StandardException.new(message, error)
    if exception.present? && status.to_i >= 500
      logger.error(exception)
      Sentry.capture_exception(exception)
    end
    return if performed?

    if ENV['SHOW_ERRORS'].to_s.to_boolean
      error_details = {
        exception: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace
      }
    end

    meta = meta.merge({
                         locale: I18n.locale,
                         msg: {
                           success: false,
                           message: message.to_s.encode('utf-8', invalid: :replace, undef: :replace),
                           error:,
                           error_details:
                         }.compact
                       })

    render json: { meta: }, status:
  end

  def render_jsonapi_msg(msg = {}, status = 200, meta = {})
    return if performed?

    render json: {
      meta: meta.merge({
                         locale: I18n.locale,
                         msg: {
                           success: true
                         }.merge(msg.is_a?(Hash) ? msg : { message: msg.to_s })
                       })
    }, status: status
  end

  class Schema
    include JSON::SchemaBuilder

    attr_accessor :single, :meta, :links

    def record_type
      self.class.module_parents.first.record_type
    end

    def schema_record
      raise <<~WARNING
        Please implement `schema_record` method in the
        Serializer::Schema subclass to return a Proc
        with the record attributes, [relationships, links, meta].
      WARNING
    end

    def record_commons
      string :created_by_user, default: 'Firstname Lastname', description: 'The user that created the record'
      string :updated_by_user, default: 'Firstname Lastname', description: 'The user that last updated the record'
    end

    def schema_links
      false
    end

    def schema_json_api_options
      proc do
        unless single
          number :limit, default: 10, description: 'page size - maximum number of records returned in a request'
          number :page, default: 1, description: 'the current page number'
        end
        object :fields,
               description: 'if the request was sent with fields parameter (comma separated field names) this shows which fields were requested'
      end
    end

    def schema_msg
      proc do
        boolean :success, default: true, description: 'indicates successful requests'
        string :error, null: true, default: nil, description: 'if unsuccessful contains an error message'
      end
    end

    def schema_meta
      proc do
        number :total, description: 'number of total records' unless single
        object :json_api_options, &schema_json_api_options
        string :locale, default: 'en', description: 'the currently selected locale'
        object :msg, description: 'info about the request', &schema_msg
      end
    end

    # The schema returned for delete requests
    def swagger_delete
      object do
        object :meta do
          string :locale, default: 'en', description: 'the currently selected locale'
          object :msg, description: 'info about the request' do
            boolean :success, default: true, description: 'indicates successful requests'
            string :message, null: true, default: nil, description: 'user friendly localized info'
            string :error, null: true, default: nil, description: 'if unsuccessful contains an error message'
            string :error_details, null: true, default: nil, description: 'more detailed error message'
          end
        end
      end
    end

    def swagger_schema_delete
      swagger_delete.schema.to_h
    end

    def swagger(**args)
      object do
        object :data, &schema_record if args[:single]
        unless args[:single]
          array :data do
            items object(&schema_record)
          end
        end
        object :meta, &schema_meta if args[:meta]
        object :links, &schema_links if args[:links] && schema_links
      end
    end

    def swagger_schema(args = {})
      args[:single] ||= false
      args[:meta] = true unless args[:meta].eql?(false)
      args[:links] ||= true unless args[:links].eql?(false)
      swagger(**args).schema.to_h
    end

    def rswag_schema(base_key: :data, except: [], only: [], required: [])
      _attributes = swagger(single: true, meta: false, links: false)
                    .schema.to_h.with_indifferent_access
                    .dig(:properties, :data, :properties, :attributes)
      [:id, except].flatten.each do |key|
        _attributes['properties'].delete key
      end
      _attributes['properties'] = _attributes['properties'].slice(*only) if [only].flatten.any?
      _attributes['required'] = required if [required].flatten.any?
      # _attributes
      {
        type: 'object',
        properties: {
          base_key => _attributes
        }
      }.deep_stringify_keys
    end

    # ---------------------------------------------------------------
    # OpenAPI 3.1.1 spec generator methods
    # ---------------------------------------------------------------

    def serializer
      self.class.module_parents.first
    end

    # Sanitized schema name for components/schemas
    def openapi_component_name
      serializer.name.gsub(/::/, '.')
    end

    def openapi_component_ref
      { '$ref': "#/components/schemas/#{openapi_component_name}" }
    end

    def openapi_component_meta_ref
      { '$ref': '#/components/schemas/meta' }
    end

    # Extracts the attributes portion from schema_record for use in components/schemas
    def openapi_component_produces_schema
      @openapi_component_produces_schema ||= begin
        _schema = schema_record.call.schema.to_h.with_indifferent_access
        # identity-management schemas wrap fields in id/type/attributes structure
        _attributes = _schema.dig(:properties, :attributes) || _schema
        _attributes
      end
    end

    # Request body schema for JSON (create/update)
    def openapi_consumes_schema(only: nil)
      return empty_consumes_schema if only == []

      only = only&.collect(&:to_s)
      _attributes = openapi_component_produces_schema.deep_dup

      # drop read_only fields
      _attributes[:properties]&.each do |key, prop|
        _attributes[:properties].delete(key) if prop[:readOnly] || prop['readOnly']
      end

      # apply only filter
      if only.try(:any?)
        _attributes[:properties] = _attributes[:properties].slice(*only)
      end

      {
        type: :object,
        properties: {
          data: _attributes
        }
      }.deep_symbolize_keys
    end

    # Request body schema for form-data (multipart)
    def openapi_consumes_form_data_schema(only: nil)
      return empty_consumes_schema if only == []

      _schema = openapi_consumes_schema(only:)
      _flattened = flatten_openapi_form_data(_schema[:properties][:data], prefix: 'data')

      {
        type: :object,
        required: _flattened[:required].presence,
        properties: _flattened[:fields].sort.to_h
      }.compact
    end

    # Response schema for index (list) endpoints
    def openapi_produces_schema_index
      {
        type: :object,
        required: %i(data),
        description: 'List endpoints will return an array below data',
        properties: {
          data: {
            type: :array,
            items: {
              type: :object,
              required: %i(id type attributes),
              properties: {
                id: { type: :string },
                type: { type: :string, default: record_type },
                attributes: openapi_component_ref
              }
            }
          },
          meta: openapi_component_meta_ref
        }
      }.deep_stringify_keys
    end

    # Response schema for show/create/update endpoints
    def openapi_produces_schema
      {
        type: :object,
        required: %i(data),
        description: 'Single endpoints will return an object as data',
        properties: {
          data: {
            type: :object,
            required: %i(id type attributes),
            properties: {
              id: { type: :string },
              type: { type: :string, default: record_type },
              attributes: openapi_component_ref
            }
          },
          meta: openapi_component_meta_ref
        }
      }.deep_stringify_keys
    end

    # Meta-only response schema (for delete)
    def openapi_meta_schema
      meta_schema = swagger_schema_delete
      meta_schema
    end

    # Default schemas shared across all specs
    def openapi_default_schemas
      {
        locales: { type: :string, enum: I18n.available_locales },
        meta: swagger_schema_delete.dig('properties', 'meta') || swagger_delete.schema.to_h.dig('properties', 'meta')
      }
    end

    def openapi_component_locales_ref
      { '$ref': '#/components/schemas/locales' }
    end

    private

    def empty_consumes_schema
      {
        type: :object,
        description: 'This endpoint does not support sending any attributes',
        nullable: true
      }
    end

    def flatten_openapi_form_data(obj, prefix: 'data')
      _schema_required = (obj[:required] || []).collect(&:to_sym)
      _required = []
      _fields = []

      (obj[:properties] || {}).each do |k, v|
        if v[:type].to_s.to_sym.eql?(:object)
          _prefix = "#{prefix}[#{k}]"
          _append = flatten_openapi_form_data(v, prefix: _prefix)
          _fields |= _append[:fields]
          _required |= _append[:required]
        else
          _name = "#{prefix}[#{k}]"
          _required << _name if _schema_required.include?(k.to_sym)
          _fields << [_name, v]
        end
      end
      { fields: _fields, required: _required }
    end
  end

  # standardized schema for simple uploads
  # just define Schema within a serializer from this
  #    class Schema < JsonApi::SchemaUpload; end
  class SchemaUpload < Schema
    def schema_record
      proc do
        string :id, description: 'unique record id'
        string :type, description: 'defines the class of the data'
        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :name, description: 'file name'
        end
        object :links do
          string :document, description: 'URL to the downloadable file'
        end
      end
    end
  end
end
