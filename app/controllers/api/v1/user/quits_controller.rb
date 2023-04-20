class Api::V1::User::QuitsController < Api::V1::JsonApiController

  MODEL_BASE = User
  MODEL = -> { 
    current_user.actor.mappings.where(parent_ids: params_json_api[:id])
  }
  SERIALIZER = AppSerializer

  SWAGGER = {
    tag: 'Current User'
  }

  undef_method :index
  undef_method :show
  undef_method :create
  undef_method :update

  def destroy
    _deleted = current_user.actor.mappings.where(parent_ids: params_json_api[:id]).destroy_all
    render_jsonapi_msg({
      success: !!_deleted,
      message: nil,
      error: (!!_deleted ? nil : :quit_failed),
      error_details: (!!_deleted ? nil : I18n.t('errors.user.quit_failed')),
    }, (!!_deleted ? 200 : 409))
  end

  private
  def cando
    CANDO.merge({
      destroy: %w(public) # no CANDO required to leave an app
    })
  end

end
