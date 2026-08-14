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

    # SECURITY / PENTEST NOTE (issue #2419): do NOT split this into a distinct
    # "user not found" vs "no recovery email configured" response. A separate
    # 404 for non-existent accounts let an attacker enumerate registered email
    # addresses (Cognisys pentest finding, July 2026). Both cases must render
    # the exact same status/message so the response carries no signal about
    # whether the email is registered.
    unless recovery_user.is_a?(User) && recovery_user.recovery_email
      render_jsonapi_error(I18n.t('errors.user.recovery_token.recovery_email_unset'), 'record_error', 400) and return
    end

    recovery_user.app_context = params[:app]
    recovery_user.send_recovery_instructions

    render_jsonapi_msg({
      success: true,
      message: I18n.t('devise.mailer.recovery_instructions.started')
    }, 200)
  end

end
