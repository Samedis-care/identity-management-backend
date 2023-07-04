class Api::V1::UsersController < Api::V1::JsonApiController

  MODEL_BASE = User
  MODEL = User.available
  MODEL_OVERVIEW = User.available
  SERIALIZER = UserSerializer
  OVERVIEW_SERIALIZER = UserOverviewSerializer

  PERMIT_CREATE = PERMIT_UPDATE = [
    :image_b64,
    :image,
    :pwd_reset_uid,
    :active,
    :email,
    :picture,
    :locale,
    :set_password,
    :new_password,
    :new_password_verify,
    :title,
    :first_name,
    :last_name,
    :short,
    :gender,
    :invalid_at,
    :mobile
  ]

  private
  def cando
    CANDO.merge({
      show:    %w(identity-management/global.admin+identity-management/users.reader),
      index:   %w(identity-management/global.admin+identity-management/users.reader),
      create:  %w(identity-management/global.admin+identity-management/users.writer),
      update:  %w(identity-management/global.admin+identity-management/users.writer),
      destroy: %w(identity-management/global.admin+identity-management/users.deleter)
    })
  end

  def record_update
    user = model_update.find(params_json_api[:id])
    user.disable_devise_notifications!
    user.skip_reconfirmation! if params_json_api.dig(:data, :email).present?
    user
  end

  def record_create
    user = model_create.create(params_create.merge({ app_context: 'identity-management', confirmed_at: Time.now}))
    user.disable_devise_notifications!
    user
  end

end
