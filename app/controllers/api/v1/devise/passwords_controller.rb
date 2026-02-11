module Api::V1::Devise
  class PasswordsController < Devise::PasswordsController
    respond_to :json
    respond_to :html, only: []
    respond_to :xml, only: []
    include BaseControllerMethods

    MODEL_BASE = User
    SERIALIZER = OVERVIEW_SERIALIZER = AppUserSerializer

    # POST /resource/password
    def create
      email = params.dig(:user, :email).to_s.downcase
      user = User.login_allowed.where(email: email).first
      if user.present?
        if user.reset_password_sent_at && user.reset_password_sent_at > 5.minutes.ago
          render_jsonapi_error(I18n.t('devise.mailer.reset_password_delayed', email: email), 'reset_password_delayed', 400) and return
        end
        user.app_context = current_app
        user.send_reset_password_instructions
      end
      render_jsonapi_msg({ success: true, message: I18n.t('devise.mailer.reset_password_msg', email: email) }, 200)
    end

    # PUT /resource/password
    # config/initializers/devise.rb is the place to configure how long a token is valid
    # e.g. `config.reset_password_within = 24.hours`
    def update
      original_token = params.dig(:user, :reset_password_token)
      reset_password_token = Devise.token_generator.digest(resource_class, :reset_password_token, original_token)
      user = User.login_allowed
                 .where(:reset_password_token => reset_password_token,
                        :reset_password_sent_at.gte => Devise.reset_password_within.ago).first

      if user.nil?
        Sentry.capture_message("reset_token_invalid - original_token: #{original_token} / reset_password_token: #{reset_password_token} / reset_password_sent_at.gte: #{Devise.reset_password_within.ago}")
        render_jsonapi_error(I18n.t('auth.error.password_token_invalid'), 'reset_token_invalid', 400) and return
      else
        user.app_context = current_app
        # not using default method to change password since it triggers mail notification
        # and that mail wouldn't get the app_context this way
        #self.resource = resource_class.reset_password_by_token(resource_params)

        if user.persisted?
          if user.reset_password_period_valid?
            # if required, auto confirm email at the same time as the
            # reset token was sent via mail
            user.confirmed_at ||= Time.now
            user.reset_password(resource_params[:password], resource_params[:password_confirmation])
          else
            user.errors.add(:reset_password_token, :expired)
          end
        end

        if user.errors.empty?
          user.unlock_access! if unlockable?(user) # this also removes multi fail login caused lock (from lockable)
          user.update(reset_password_token: nil, reset_password_sent_at: nil)
          # changed password revokes all current logins of this user
          Doorkeeper::AccessToken.where(resource_owner_id: user.id).each &:revoke
          render_jsonapi_msg({ success: true, message: I18n.t('devise.mailer.password_change.header', user_name: user.name) }, 200) and return
        else
          render_jsonapi_error(user.errors.full_messages*', ', 'error', 400) and return
        end
      end

    end
  end
end