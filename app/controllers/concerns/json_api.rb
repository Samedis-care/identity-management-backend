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
    Sentry.capture_exception(exception) if exception.present? && status.to_i >= 500
    return if performed?

    render json: {
      meta: meta.merge({
                         locale: I18n.locale,
                         msg: {
                           success: false,
                           message: message.to_s.encode('utf-8', invalid: :replace, undef: :replace),
                           error: error
                         }
                       })
    }, status: status
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
