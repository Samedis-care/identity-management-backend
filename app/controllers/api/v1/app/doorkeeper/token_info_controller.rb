class Api::V1::App::Doorkeeper::TokenInfoController < Doorkeeper::TokenInfoController
  include AbstractController::Callbacks
  include JsonApi
  include SetLocale
  include BaseControllerMethods

  MODEL_BASE = User
  SERIALIZER = OVERVIEW_SERIALIZER = AppUserSerializer

  SWAGGER = {
    tag: 'Access Tokens'
  }

  before_action :set_locale

  def show
    if doorkeeper_token && doorkeeper_token.accessible?
      user = User.login_allowed.find(doorkeeper_token.resource_owner_id) rescue nil
      if user.is_a?(User)
        user.app_context = current_app(doorkeeper_token)
        render json: AppUserSerializer.new(user, {
          meta: { 
            msg:{ success: true },
            app: user.app_context
          }
        })
      end
    end

    unless performed?
      render_jsonapi_error(I18n.t('auth.error.token_invalid'), 'token_invalid', 401) and return
    end

  end

  private

end
