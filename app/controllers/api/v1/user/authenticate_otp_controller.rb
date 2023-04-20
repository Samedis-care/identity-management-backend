class Api::V1::User::AuthenticateOtpController < Api::V1::JsonApiController

  rescue_from IdentityManagementExtension::OtpTooManyTries, with: :otp_too_many_tries

  skip_before_action :authorize, only: [:create]

  MODEL_BASE = Doorkeeper::AccessToken
  MODEL = -> {
    current_user.active_logins.order(created_at: -1)
  }
  SERIALIZER = AccountLoginSerializer

  SWAGGER = {
    tag: 'Current User'
  }

  undef_method :index
  undef_method :update
  undef_method :show
  undef_method :destroy

  def create
    # supply otp if required
    if current_token.authenticate_otp(params[:data][:authenticate_otp])
      render_jsonapi_msg({ success: true }) and return
    else
      render_jsonapi_msg({
        success: false,
        error: 'otp_invalid',
        message: I18n.t('auth.error.otp_invalid')
      }) and return
    end
  end

  private

  def otp_too_many_tries(e)
    render_jsonapi_msg({
      success: false,
      error: 'otp_too_many_tries',
      message: e.message
    }) and return
  end

  def cando
    CANDO.merge({
      create: %w(public) # no CANDO required
    })
  end

end
