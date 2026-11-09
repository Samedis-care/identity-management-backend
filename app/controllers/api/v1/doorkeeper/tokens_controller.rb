# OpenAPI spec: spec/openapi/public/paths/api/v1/doorkeeper/tokens.yaml
class Api::V1::Doorkeeper::TokensController < Doorkeeper::TokensController
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

  undef_method :create # use :app/doorkeeper/tokens#create as app context is required for redirects

  def revoke
    token = params[:access_token] || bearer_token
    token_type_hint = params[:token_type_hint] || 'refresh_token'

    if token.present?
      # will find the token record regardless of token type (access or refresh)
      tokens_to_revoke = Doorkeeper::AccessToken.or({ token: token}, { refresh_token: token }).to_a
      tokens_to_revoke.each do |_token|
        if token_type_hint.downcase.eql?('access_token')
          # expires the access token, but leaves the refresh_token still valid
          _token.update_attributes(expires_in: -1)
        else
          # invalidates the whole token by revoking the refresh token
          _token.revoke
        end
      end
      render_jsonapi_msg({ success: tokens_to_revoke.any? }, 200, logout_meta(tokens_to_revoke)) and return
    end

    render_jsonapi_error(I18n.t('auth.error.token_invalid'), 'invalid_token', 403, meta: { token: token }) and return
  end

  private

  # For a session that came from a CustomAuthProvider SSO login, the client
  # must also end the IdP session, or the next authorize request on a shared
  # device passes straight through as the previous user. Returned on both
  # revoke branches: the samedis-care frontend logs out with
  # token_type_hint: 'access_token' whenever it holds a refresh token, which
  # every SSO login does (Samedis-care/samedis-care-issues#3666).
  def logout_meta(tokens)
    token = tokens.detect { |t| t.im_sso_provider.present? }
    return {} unless token

    provider = CustomAuthProvider.where(domain: token.im_sso_provider).first
    logout_url = provider&.logout_url(state: { app: token.im_app }.to_json)
    logout_url ? { logout_url: } : {}
  end

end
