class Api::V1::App::Doorkeeper::TokensController < Doorkeeper::TokensController
  include AbstractController::Callbacks
  include JsonApi
  include SetLocale
  include BaseControllerMethods

  MODEL_BASE = User
  SERIALIZER = OVERVIEW_SERIALIZER = AppUserSerializer

  SWAGGER = {
    tag: 'Access Tokens'
  }

  before_action :set_locale

  def create
    grant_type = params[:grant_type].to_s.strip.downcase

    if Doorkeeper.configuration.token_grant_types.exclude?(grant_type)
      render_jsonapi_error(I18n.t('auth.error.grant_type_invalid'), 'grant_type_invalid', 400) and return
    end
    response = authorize_response

    _im_otp_provided = false
    # revoke used refresh_token
    if grant_type.eql?('refresh_token')
      _previous_token = Doorkeeper::AccessToken.find_by(refresh_token: params[:refresh_token])
      if _previous_token
        _im_otp_provided = !!_previous_token.im_otp_provided
        #_previous_token.revoke
        # instead of revoking, keep the initial bearer token until it expires
        # set refresh token to random value to invalidate it
        _previous_token.refresh_token = Doorkeeper::OAuth::Helpers::UniqueToken.generate
        _previous_token.save!
      end
    end

    if response.class.name.eql? 'Doorkeeper::OAuth::ErrorResponse'
      render_jsonapi_error(I18n.t('auth.error.login_incorrect'), 'login_incorrect', 401) and return
    elsif response.class.name.eql? 'Doorkeeper::OAuth::InvalidRequestResponse'
      render_jsonapi_error(I18n.t('auth.error.invalid_request'), 'invalid_request', 400) and return
    else
      headers.merge! response.headers
      _token_attrs = {
        im_app: params[:app],
        im_ip: request.remote_ip,
        im_navigator: request.user_agent,
        im_otp_provided: _im_otp_provided,
        expires_in: Doorkeeper.configuration.access_token_expires_in
      }
      response.token.update_attributes(**_token_attrs)

      user = User.login_allowed.find(response.token.resource_owner_id)
      if user.nil? # handle inactive or deleted
        render_jsonapi_error(I18n.t('auth.error.login_incorrect'), 'login_incorrect', 401) and return
      end
      if user.confirmed?
        app_context = current_app(response.token)
        unless User.per_app_settings[app_context.to_sym]
          render_jsonapi_error(I18n.t('errors.invalid_app'), 'invalid_app', 400) and return
        end
        user.update_tracked_fields!(request)

        # ensure minimum access to the app the user just logged in
        # by adding them to the app users
        current_app_actor.container_users.map_into! user

        # if user redirect_host matches the whitelist
        # the url from params will later be used for redirect_url_authenticated
        # redirect_path will be added to frontend url to return to initially
        # requested url before login
        user.redirect_host = params[:redirect_host]
        user.redirect_path = params[:redirect_host] || params[:redirect_path]

        if params[:invite_token].present?
          invite = Invite.unclaimed.where(token: params[:invite_token]).first
          if invite&.target_url
            user.redirect_host = invite.target_url
            user.redirect_path = invite.target_url
          end
        end

        user.app_context = app_context
        url_values = {
          HOST: user.host,
          REDIRECT_PATH: user.redirect_path,
          APP: user.app_context,
          REMEMBER_ME: params[:remember_me].to_s.eql?('true'),
          TOKEN: response.token.token,
          REFRESH_TOKEN: response.token.refresh_token,
          TOKEN_EXPIRE: response.token.expires_in.seconds.from_now.to_i*1000,
          INVITE_TOKEN: params[:invite_token].to_s
        }
        opts = {
          meta: {
            msg:{ success: true },
            token: response.token.token,
            refresh_token: response.token.refresh_token,
            expires_in: response.token.expires_in,
            redirect_url: user.redirect_url_authenticated(url_values),
            app: user.app_context
          }
        }
        # if an invite token is supplied this will be personalized with the user_id
        user.claim_invite_token!(params[:invite_token])
        opts[:meta][:check_acceptances] = user.check_acceptances
        if params[:invite_token].present?
          opts[:meta][:invite_token] = params[:invite_token]
        end
        render json: AppUserSerializer.new(user, opts).serializable_hash
      else
        render_jsonapi_error(I18n.t('devise.user.unverified'), 'user_unverified', 403) and return
      end
    end
  end

end
