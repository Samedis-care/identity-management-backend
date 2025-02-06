class Api::V1::Devise::ConfirmationsController < Devise::ConfirmationsController
  include ActionController::Helpers
  # include ActionController::Flash
  include BaseControllerMethods

  MODEL_BASE = User
  SERIALIZER = OVERVIEW_SERIALIZER = AppUserSerializer

  respond_to :json
  respond_to :html, only: []
  respond_to :xml, only: []

  # GET /resource/confirmation?confirmation_token=abcdef
  def show
    user = resource_class.confirm_by_token(params[:confirmation_token])
    if user.errors.empty?
      user.app_context = current_app
      user.invite_token = params[:invite_token]
      _message = if params[:reason] == 'email_change'
                   I18n.t('devise.mailer.email_change_confirm')
                 else
                   I18n.t('devise.mailer.account_confirm')
                 end

      render json: AppUserSerializer.new(user, {
        meta: {
          msg: {
            success: true,
            message: _message
          },
          redirect_url: User.redirect_url_login(user.app_context, invite_token: params[:invite_token]),
          app: user.app_context
        }
      })
    else
      message = I18n.t('auth.error.token_invalid')
      error = 'invalid_token'

      if user.is_a?(User) && user.errors.any?
        message = user.errors.full_messages * ', '
        error = 'record_error'

        errors = user.errors.collect { [it.attribute, it.type].join('_').underscore }
        if errors.include?('confirmation_token_invalid')
          message = I18n.t('auth.error.confirmation_token_invalid')
          error = 'confirmation_token_invalid'
        end
      end
      render_jsonapi_error(message, error, 400)
    end
  end

  # GET /users/recovery_confirmation/:recovery_confirmation_token
  def recovery_confirmation
    user = resource_class.confirm_by_recovery_token(params[:recovery_confirmation_token])

    if user.is_a?(User) && user.errors.empty?
      user.app_context = current_app
      render json: AppUserSerializer.new(user, {
        meta: {
          msg: {
            success: true,
            message: I18n.t('devise.mailer.recovery_email_confirm')
          },
          redirect_url: User.redirect_url_login(user.app_context, invite_token: params[:invite_token]),
          app: user.app_context
        }
      })
    elsif user.is_a?(User)
      render_jsonapi_error(user.errors.full_messages*', ', 'error', 400)
    else
      render_jsonapi_error(I18n.t('auth.error.token_invalid'), 'invalid_token', 400)
    end
  end

  # POST /resource/confirmation
  def create
    email = params.dig(:user, :email).to_s.downcase
    invite_token = params.dig(:invite_token).to_s
    user = User.login_allowed.where(email: email, confirmed_at: nil).first

    if user.present?
      user.app_context = current_app
      user.invite_token = invite_token
      user.send_confirmation_instructions
    end

    if user.nil? || successfully_sent?(user)
      render_jsonapi_msg({ success: true, message: I18n.t('devise.mailer.account_confirm_resend', email: email) }, 200)
    else
      render_jsonapi_error(user.errors.full_messages*', ', 'error', 400)
    end
  end

  private
  def app_confirm_account_url
    return nil if current_app.blank?
    auth_redirects[Rails.env][current_app][:confirm_account]
  end

  def auth_redirects
    YAML::load_file(Rails.root.join('config', 'auth_redirects.yml'))
  end

end
