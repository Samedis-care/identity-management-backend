# Native mobile social login endpoint.
#
# iOS/Android apps use their native SDK (Google Sign-In, Apple Sign In,
# Microsoft MSAL) to authenticate the user, then send the signed id_token
# here for verification + Doorkeeper token exchange.
#
# This does NOT touch the browser-redirect OmniAuth flow which continues
# to work unchanged for web logins.
#
class Api::V1::App::SocialAuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_maintenance_mode

  SWAGGER = {
    tag: 'Social Authentication'
  }.freeze

  # POST /api/v1/:app/auth/social
  def create
    provider = params[:provider].to_s.downcase
    id_token = params[:id_token]

    if provider.blank? || id_token.blank?
      render_jsonapi_error(
        I18n.t('auth.error.social_missing_params'),
        'invalid_request', 400
      ) and return
    end

    # 1. Verify the JWT signature, issuer, audience, expiry
    verifier = SocialTokenVerifier.new(provider:, id_token:)
    claims = verifier.verify!

    # 2. Build an OmniAuth-compatible auth hash and find/create the user
    auth = build_auth_hash(provider, claims)
    user = User.from_omniauth(auth)
    user.app_context = current_app

    # Handle Apple first-sign-in name (only sent once by Apple)
    if provider == 'apple' && params[:name].present?
      user.first_name = params.dig(:name, :first) if params.dig(:name, :first).present?
      user.last_name = params.dig(:name, :last) if params.dig(:name, :last).present?
      user.save! if user.changed?
    end

    unless user.errors.empty?
      render_jsonapi_error(
        user.errors.full_messages.join(', '),
        'oauth_error', 422
      ) and return
    end

    unless user.confirmed?
      render_jsonapi_error(
        I18n.t('devise.user.unverified'),
        'user_unverified', 403
      ) and return
    end

    # 3. Issue Doorkeeper access + refresh token
    token = Doorkeeper::AccessToken.create(
      use_refresh_token: true,
      resource_owner_id: user.id,
      expires_in: Doorkeeper.configuration.access_token_expires_in,
      scopes: 'api',
      im_otp_required: false,
      im_app: current_app,
      im_ip: request.remote_ip.to_s.to_utf8.presence,
      im_navigator: request.user_agent.to_s.to_utf8.presence
    )

    # 4. Ensure minimum app access
    current_app_actor&.container_users&.map_into!(user)

    user.update_tracked_fields!(request)
    user.claim_invite_token!(params[:invite_token]) if params[:invite_token].present?

    # 5. Respond with the same structure as the password grant
    opts = {
      meta: {
        msg: { success: true },
        token: token.token,
        refresh_token: token.refresh_token,
        expires_in: token.expires_in,
        app: current_app
      }
    }

    render json: AppUserSerializer.new(user, opts).serializable_hash.merge(
      token_type: 'Bearer',
      access_token: token.token,
      refresh_token: token.refresh_token,
      expires_in: token.expires_in
    )

  rescue SocialTokenVerifier::VerificationError => e
    render_jsonapi_error(e.message, 'social_auth_failed', 401)
  end

  private

  def current_app
    @current_app ||= params[:app].to_s.gsub(/\./, '-').to_slug
  end

  def current_app_actor
    @current_app_actor ||= Actors::App.named(current_app).first
  end

  def build_auth_hash(provider, claims)
    OpenStruct.new(
      provider: provider_name(provider),
      uid: claims['sub'],
      credentials: OpenStruct.new(
        token: nil,
        refresh_token: nil,
        expires: false,
        expires_at: nil
      ),
      info: OpenStruct.new(
        email: claims['email']&.downcase,
        name: claims['name'],
        first_name: claims['given_name'],
        last_name: claims['family_name'],
        locale: claims['locale']
      )
    )
  end

  def provider_name(provider)
    case provider
    when 'google' then 'google_oauth2'
    when 'apple' then 'apple'
    when 'microsoft' then 'microsoft_graph'
    else provider
    end
  end
end
