class Api::V1::Devise::OmniauthCallbacksController < Devise::OmniauthCallbacksController

  include BaseControllerMethods

  def failure
    _uri = URI.parse(User.redirect_url_login(current_app, invite_token: invite_token||''))
    _uri.query = { failure_message: failure_message }.to_query
    redirect_to _uri.to_s
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
      TOKEN_EXPIRE: token.expires_in.seconds.from_now.to_i*1000,
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

  # def facebook
  #   do_oauth
  # end

  # def twitter
  #   do_oauth
  # end

  def apple
    do_oauth
  end

  def dynamic_provider_authorize
    provider = CustomAuthProvider.find_by(domain: params[:provider])
    state = params[:state]
    login_hint = params[:login_hint] # optionally pass through the email address
    session[:code_verifier] = code_verifier = provider.code_verifier # @TODO !!
    redirect_to provider.passthru_uri(code_verifier:, state:, login_hint:), allow_other_host: true
  end

  def dynamic_provider_callback
    code = params[:code]
    session_state = params[:session_state]
    provider = CustomAuthProvider.find_by(domain: params[:provider])
    user = provider.user_info(code)

    _debug = []
    _debug << "#{params[:provider]} user: #{JSON.pretty_generate(user)}"
    _debug << "=" * 80
    render plain: _debug.join("\n") and return
    # - use provider.user_info to load or create a user
    # - create a Doorkeeper::AccessToken
    # - redirect to frontend
  end

  private
  def user
    @user ||= begin
      _user = User.from_omniauth(auth)
      _user.app_context = current_app
      _user.invite_token = invite_token
      case params[:action].to_sym
        when :apple, :microsoft_graph, :google_oauth2
          _user.redirect_host = state.dig(:redirect_host)
          _user.redirect_path = state.dig(:redirect_host)
        else
          _user.redirect_host = params[:redirect_host]
          _user.redirect_path = params[:redirect_host]
      end
      _user
    end
  end

  def current_app
    state[:app].gsub(/\./,'-').to_slug
  end

  def oauth_params
    request.env["omniauth.params"]
  end

  def auth
    request.env["omniauth.auth"]
  end

  def state
    (JSON.parse(params[:state]) rescue {}).with_indifferent_access
  end

  def invite_token
    state[:invite_token]
  end

end

