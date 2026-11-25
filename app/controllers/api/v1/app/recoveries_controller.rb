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
    # normalized like Devise's case_insensitive_keys / strip_whitespace_keys,
    # and to_s keeps a hash param out of the query
    email = params[:email].to_s.strip.downcase
    recovery_user = User.login_allowed.where(email: email).first

    # SECURITY / PENTEST NOTE (issues #2419, #2562): every branch - no such
    # user, user without recovery email, user with recovery email - must
    # render the one generic response below. Any distinct status or message
    # (the former 404, and later the 400 "no recovery email configured")
    # tells an attacker whether the address is registered. The mail is sent
    # silently, only when a recovery email is configured.
    if recovery_user.is_a?(User) && recovery_user.recovery_email.present?
      recovery_user.app_context = params[:app]
      recovery_user.send_recovery_instructions
    end

    render_jsonapi_msg({
      success: true,
      message: I18n.t('devise.mailer.recovery_instructions.started')
    }, 200)
  end

end
