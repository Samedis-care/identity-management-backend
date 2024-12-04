class Api::V1::Devise::OmniauthCallbacksController < Devise::OmniauthCallbacksController

  include SetLocale
  include BaseControllerMethods

  before_action :set_locale

  rescue_from CustomAuthProvider::UntrustedEmailError, with: :oauth_error
  rescue_from CustomAuthProvider::FailedAuthError, with: :oauth_error

  # for CustomAuthProvider this sets the standard failure_message
  def oauth_error(e)
    request.env['omniauth.error.strategy'] = params[:provider]
    request.env['omniauth.error.type'] = e.message

    failure
  end

  def do_oauth
    unless user.errors.empty?
      generic_error(user.errors)
      login_url = URI.parse(User.redirect_url_login(user.app_context, invite_token: user.invite_token) % { HOST: user.host })
      q = Hash[URI.decode_www_form(login_url.query || '')].merge({
        error: 'oauth_incomplete',
        message: (user.errors.keys - [:password]).join(',')
      })
      login_url.query = URI.encode_www_form(q)
      redirect_to login_url.to_s and return
    end

    token = Doorkeeper::AccessToken.create(
      use_refresh_token: true,
      resource_owner_id: user.id,
      expires_in: Doorkeeper.configuration.access_token_expires_in,
      scopes: 'api',
      im_otp_required: false,
      im_app: user.app_context,
      im_ip: request.remote_ip,
      im_navigator: request.user_agent
    )

    url_values = {
      HOST: user.host,
      REDIRECT_PATH: user.redirect_path,
      APP: user.app_context,
      TOKEN: token.token,
      REFRESH_TOKEN: token.refresh_token,
      TOKEN_EXPIRE: token.expires_in.seconds.from_now.to_i * 1000,
      INVITE_TOKEN: user.invite_token
    }
    # if an invite token is supplied this will be personalized with the user_id
    user.claim_invite_token!(user.invite_token)
    user.auto_accept_invites!
    redirect_to Addressable::URI.parse(user.redirect_url_authenticated(url_values)).to_s, allow_other_host: true
  end

  def google_oauth2
    do_oauth
  end

  def microsoft_graph
    do_oauth
  end

  def apple
    do_oauth
  end

  def dynamic_provider_authorize
    _domain = params[:provider]
    provider = CustomAuthProvider.where('$or': [{ domain: _domain }, { trusted_email_domains: _domain }]).first

    state = params[:state]
    if !state && params[:app]
      state = { app: current_app_actor.name, redirect_host: current_app_actor.config.url }.to_json
    end
    # pass on requested locale
    state = JSON.parse(state).merge(locale: I18n.locale).to_json

    code_verifier = provider.create_code_verifier!
    cookies[:code_verifier] = { value: code_verifier, expires: 3.minutes }

    redirect_to provider.passthru_uri(code_verifier:, state:, login_hint: params[:login_hint]), allow_other_host: true
  end

  def dynamic_provider_callback
    code = params[:code]
    provider = CustomAuthProvider.find_by(domain: params[:provider])
    user_info = provider.access_token(code, code_verifier: cookies[:code_verifier])
    request.env['omniauth.auth'] = provider.auth(user_info)

    do_oauth
  end

  private

  def user
    @user ||= begin
      _user = User.from_omniauth(auth)
      _user.app_context = current_app
      _user.invite_token = invite_token
      _user.redirect_path = _user.redirect_host = state[:redirect_host] || params[:redirect_host]
      _user
    end
  end

  def current_app
    (state[:app] || params[:app]).to_s.gsub(/\./, '-').to_slug
  end

  def oauth_params
    request.env['omniauth.params']
  end

  def auth
    request.env['omniauth.auth']
  end

  def state
    @state ||= (JSON.parse(params[:state]) rescue {}).with_indifferent_access
  end

  def invite_token
    state[:invite_token]
  end

  def set_locale
    I18n.locale = state[:locale].presence || super
  end

  protected

  def failure
    redirect_to after_omniauth_failure_path_for, allow_other_host: true
  end

  def after_omniauth_failure_path_for(_scope = nil)
    _uri = URI.parse(User.redirect_url_login(current_app, invite_token: invite_token || ''))
    _uri.query = { failure_message:, redirect_host: state[:redirect_host] }.to_query
    _uri.to_s
  end

end
