class Api::V1::App::RecoveriesController < ApplicationController

  # via POST this starts the recovery process that creates a short lived (5 minutes)
  # recovery token which can be used as a password (grant_type password) with the regular
  # create action here if additionally to the regular email the `recovery_email`
  # is supplied.
  # This recovery token will be sent as an email which will redirect to a special
  # frontend part that will then initiate the login.
  # When the login happens the user will be forcefully removed from any tenant membership
  # for security reasons as the sole purpose is to allow further access to existing app data
  # for the user which doesn't require tenant privileges.
  def create
    recovery_user = User.login_allowed.where(email: params[:email]).first
    recovery_user.send_recovery_instructions

    render_jsonapi_msg({
      success: true,
      message: I18n.t('devise.mailer.recovery_instructions.started')
    }, 200)
  end

end
