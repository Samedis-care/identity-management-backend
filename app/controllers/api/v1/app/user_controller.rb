# This controller handles a single users own data
# For the users of an App look at users_controller !
class Api::V1::App::UserController < Api::V1::JsonApiController

  MODEL_BASE = User
  MODEL = User
  SERIALIZER = AppUserSerializer
  OVERVIEW_SERIALIZER = AppUserSerializer

  SWAGGER = {
    tag: 'Current User'
  }

  undef_method :create
  undef_method :show

  PERMIT_CREATE = []
  PERMIT_UPDATE = [
    :app,
    :first_name,
    :last_name,
    :image,
    :image_b64,
    :gender,
    :email,
    :email_confirmation,
    :mobile,
    :title,
    :short,
    :otp_enable,
    :otp_disable
  ]

  def index
    show
  end

  def show
    render_serialized_record(
      record: record_show,
      meta: { app: record_show.app_context }
    )
  end

  def update
    begin
      user = record_update
      if params_update_with_password[:password].present?
        user.update_with_password(params_update_with_password)
        # delete all but current token of this user
        Doorkeeper::AccessToken.where(resource_owner_id: user.id, :token.ne => bearer_token).delete_all
      else
        user.attributes=params_update
        user.save
      end
      check_for_errors(user) || return
      success = true
      error = nil
    rescue => e
      success = false
      error = e.message
    end
    render_serialized_record(
      record: user,
      success: success,
      error: error,
      meta: { app: user.app_context }
    )
  end

  private
  def record_update
    current_user.app_context = current_app if current_user.app_context.blank?
    current_user
  end

  def record_show
    record_update
  end

  def record_destroy
    record_update
  end

  def records_destroy
    [record_update]
  end

  def cando
    CANDO.merge({
      all: %w(public) # no CANDO required to edit own user info
    })
  end

  def params_update_with_password
    params.fetch(:data, {}).permit *(self.class::PERMIT_UPDATE + [:current_password, :password, :password_confirmation])
  end

end
