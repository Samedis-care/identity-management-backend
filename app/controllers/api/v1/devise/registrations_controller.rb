class Api::V1::Devise::RegistrationsController < Devise::RegistrationsController
  include ActionController::Helpers
  include ActionController::Flash
  include BaseControllerMethods
  respond_to :json

  MODEL_BASE = User
  SERIALIZER = OVERVIEW_SERIALIZER = AppUserSerializer
  PERMIT_CREATE = [
    :captcha,
    :email,
    :email_confirmation,
    :password,
    :password_confirmation,
    :first_name,
    :last_name,
    :actor_id,
    :invite_token
  ]
  PERMIT_UPDATE = [
    :first_name,
    :last_name
  ]

  prepend_before_action :authenticate_scope!, only: [:edit, :update, :destroy]
  prepend_before_action :check_captcha, only: [:create]

  def not_allowed
    raise MethodNotAllowed
  end

  def create
    set_resource
    build_resource({ email_confirmation: '' }.merge(params_create))
    user = resource
    user.email = user.email.to_s.downcase
    user.email_confirmation = user.email_confirmation.to_s.downcase

    user.invite_token = sign_up_params['invite_token']

    user.app_context = current_app
    render_jsonapi_error(I18n.t('errors.missing_app'), 'missing_app', status=400) and return if user.app_context.blank?
    user.validate
    user = check_for_errors(user) || return
    _new_user = user.new_record?

    user.save!
    if user.persisted?
      if user.send(:confirmation_required?) && !_new_user
        # this triggers save with a fresh confirmation token
        # unless it's a new user which triggers this itself
        user.send_confirmation_instructions
      end
      app_name = Actors::App.named(user.app_context).first&.full_name

      intialize_doorkeeper_app
      locale_vars = { user_name: user.name, email: user.email, app_name: }
      render json: AppUserSerializer.new(user, {
        meta: { 
          msg:{ 
            success: true,
            message: I18n.t('devise.mailer.registered', **locale_vars),
            thanks_message: I18n.t('mailer.regards', **locale_vars),
          },
          app: user.app_context
        }
      })

    else
      errors = user.errors.full_messages.compact.uniq.join("\n")
      render_jsonapi_error(errors, 'error', status=400)
    end
  end


  private

  def check_captcha
    return unless ENV["RECAPTCHA_PUBLIC_KEY"]
    unless verify_recaptcha(response: params[:captcha], secret_key: ENV['RECAPTCHA_PRIVATE_KEY'])
      render_jsonapi_error(I18n.t('devise.user.recaptcha_invalid'), 'recaptcha_invalid', status=400) and return
    end
  end

  def set_resource
    params[:user] = params.slice(:email, :email_confirmation, :password, :password_confirmation, :first_name, :last_name, :actor_id, :invite_token)
  end

  def intialize_doorkeeper_app
    begin
      app_name = params[:application_name] || "Oauth-App #{resource.name}"
      Doorkeeper::Application.new(name: "#{app_name}", redirect_uri: request.base_url, owner: resource).save
     rescue => e
      Rails.logger(e.message)
    end
  end

  def params_create
    params.fetch(:user, params.fetch(:data, {})).permit(*self.class::PERMIT_CREATE)
  end

  def params_update
    params.fetch(:user, params.fetch(:data, {})).permit(*self.class::PERMIT_UPDATE)
  end

  def sign_up_params
    params_create
  end

  def update_user_params
    params_update
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:user).push(*self.class::PERMIT_UPDATE)
  end

  def update_resource(resource, params)
    resource.update_without_password(params)
  end

end
