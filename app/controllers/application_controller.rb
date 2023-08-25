class ApplicationController < ActionController::Base
  protect_from_forgery unless: -> { request.format.json? }
  include ActionController::MimeResponds
  include JsonApi
  include SetLocale
  include BaseControllerMethods

  ## supposed to work on Rails >5.2.2 but does not (API mode)
  # rescue_from ActionDispatch::Http::Parameters::ParseError do |exception|
  #   render status: 400, json: { errors: [ exception.cause.message ] }
  # end

  def process_action(*args)
    super
  rescue ActionDispatch::Http::Parameters::ParseError => e
    render_jsonapi_error(e.cause.message, 'MALFORMED_JSON', status=400, meta: {}, exception: e)
  end

  before_action :set_cache_headers
  before_action :set_locale
  before_action :check_maintenance_mode
  skip_before_action :check_maintenance_mode, only: [:health]
  skip_before_action :check_maintenance_mode, if: -> { controller_name == 'sentry' }

  def health
    unless MaintenanceMode.current.write_allowed?
      render json: { message: 'maintenance_mode', code: 400 }, status: 400
      return
    end

    if (!User.collection.count.zero? rescue false)
      render json: { message: 'ok', code: 200 }
    else
      render json: { message: 'error', code: 500 }, status: 500
    end
  end

  def check_maintenance_mode
    case params[:action]
    when 'index', 'show'
      MaintenanceMode.current.raise_error :read
      # excel or pdf responses are only available if no maintenance mode is set. it would create files on object storage for downloads
      MaintenanceMode.current.raise_error :write unless (params[:format] || 'json') == 'json'
    else
      MaintenanceMode.current.raise_error :write
    end
  end
end
