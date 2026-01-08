# Various helpers to use in controllers and rspec integration tests for rswag
# to consistently use the JSONAPI standard response object structures.
module BaseControllerMethods
  extend ActiveSupport::Concern
 
  require 'mail' # needed to handle Net::SMTP* exceptions

  included do
    include ActiveSupport::Rescuable
    rescue_from Exception, with: :general_error
    rescue_from ArgumentError, with: :argument_error
    rescue_from ApplicationDocument::AuthorizationError, with: :authorization_error
    rescue_from ApplicationDocument::GridfilterError, with: :gridfilter_error
    rescue_from Mongoid::Errors::DocumentNotFound, with: :record_not_found_error
    rescue_from Mongoid::Errors::InvalidFind, with: :record_not_found_error
    rescue_from Mongo::Error::OperationFailure, with: :database_error
    rescue_from CSV::MalformedCSVError, with: :malformed_csv_error
    rescue_from Net::SMTPSyntaxError, with: :smtp_syntax_error
    rescue_from Net::SMTPFatalError, with: :smtp_syntax_error
    rescue_from MaintenanceMode::ReadOnlyMaintenanceError, with: :read_only_maintenance_error
    rescue_from MaintenanceMode::FullMaintenanceError, with: :full_maintenance_error
    rescue_from BSON::Error::InvalidObjectId, with: :object_id_invalid_error
    rescue_from JSON::ParserError, with: :json_parser_error
  end

  private
  # get the bearer token from headers
  # note that these are not used but the devise
  # methods in lib/devise/controllers/helpers.rb
  # take care of this via authenticate_user!
  def bearer_token
    @bearer_token ||= if !Rails.env.production? && params[:bearer].present?
      params[:bearer]
    else
      request.headers.env.detect{|k,_| k.eql?('HTTP_AUTHORIZATION') }.last.gsub(/^Bearer /, '') rescue nil
    end
  end

  def current_token
    token = bearer_token
    return if token.blank?
    return unless current_user

    @current_token ||= current_user.oauth_tokens.where(token: token).first
  end

  # app actor from session! can be overwritten by supplying custom app parameter (unless app parameter is IM)
  def current_app(doorkeeper_token=nil)
    @current_app ||= begin
      if params[:app].present? && !params[:app].eql?('identity-management')
        params[:app]
      else
        (doorkeeper_token || current_token).try(:im_app) || params[:app]
      end
    end.to_s.gsub(/\_/,'-').to_slug
  end

  # app actor from params (app id)
  def current_app_actor
    @current_app_actor ||= begin
      if current_app_id.present?
        Actors::App.available.find(current_app_id)
      elsif current_app.present?
        Actors::App.available.find_by(name: current_app)
      end
    end
  end

  def current_app_container_tenants
    current_app_actor.container_tenants
  end

  def current_app_id
    Sentry.set_tags('app.id': params[:app_id])
    params[:app_id]
  end

  def current_tenant
    tenant_id = params[:tenant_id] || (current_user.tenant_context rescue '')
    Sentry.set_tags('tenant.id': tenant_id)

    tenant_id
  end

  def current_path_tenant_id
    Sentry.set_tags('tenant.id': params[:tenant_id])
    params[:tenant_id]
  end

  def current_tenant_actor
    @current_tenant_actor ||= current_app_actor.tenants.available.find(current_path_tenant_id)
  end

  def generic_error(e)
    Sentry.capture_exception(e)
  end

  def render_generic_error(e)
    raise e unless silence_errors?
    if Rails.env.production?
      generic_error(e)
      render status: 400, json: { message: e.message } and return
    else
      render status: 400, json: { message: e.message, backtrace: e.backtrace.join("\n") } and return
    end
  end

  def record_not_found_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.record_not_found_error') : e.message
    render_jsonapi_error(message, 'record_not_found_error', 404) and return
  end

  def argument_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.argument_error') : e.message
    render_jsonapi_error(message, 'argument_error', 400, exception: e) and return
  end

  def gridfilter_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.error.gridfilter_error') : e.message
    render_jsonapi_error(message, 'gridfilter_error', 400, exception: e) and return
  end

  def general_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.general_error') : e.message
    render_jsonapi_error(message, "general_error", 500, exception: e) and return
  end

  def malformed_csv_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.malformed_csv_error') : e.message
    render_jsonapi_error(message, "malformed_csv_error", 500, exception: e) and return
  end

  def smtp_syntax_error(e)
    raise e unless silence_errors?
    return if performed?

    message = Rails.env.production? ? I18n.t('json_api.smtp_syntax_error') : e.message
    render_jsonapi_error(message, 'smtp_syntax_error', 400, exception: e) and return
  end

  def read_only_maintenance_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.maintenance_readonly_error', reason: e.message) : e.message
    render_jsonapi_error(message, "maintenance_readonly", 400, exception: e) and return
  end

  def full_maintenance_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.maintenance_error', reason: e.message) : e.message
    render_jsonapi_error(message, "maintenance", 400, exception: e) and return
  end

  def object_id_invalid_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.object_id_invalid_error', { reason: e.message }) : e.message
    render_jsonapi_error(message, "object_id_invalid", 400, exception: e) and return
  end

  def json_parser_error(e)
    raise e unless silence_errors?
    return if performed?
    message = e.message
    render_jsonapi_error(message, 'malformed_json', status=400, meta: {}, exception: e) and return
  end

  def database_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.database_error') : e.message
    render_jsonapi_error(message, "database_error", 500, exception: e) and return
  end

  def authorization_error(e)
    raise e unless silence_errors?
    return if performed?
    message = Rails.env.production? ? I18n.t('json_api.authorization_error') : e.message
    render_jsonapi_error(message, 'authorization_error', 403, exception: e) and return
  end

  def set_cache_headers
    response.headers["Cache-Control"] = "no-cache, no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end

  def console?
    (defined?(Rails::Console) rescue false)
  end

  def silence_errors?
    return false if params.key?(:debug)
    return true if Rails.env.production?
    return false if Rails.env.development?
    return false if Rails.env.local_dev?
    true
  end

end