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
      tokens_to_revoke = Doorkeeper::AccessToken.or({ token: token}, { refresh_token: token })
      tokens_to_revoke.each do |_token|
        if token_type_hint.downcase.eql?('access_token')
          # expires the access token, but leaves the refresh_token still valid
          _token.update_attributes(expires_in: -1)
        else
          # invalidates the whole token by revoking the refresh token
          _token.revoke
        end
      end
      render_jsonapi_msg({ success: tokens_to_revoke.any? }) and return
    end

    render_jsonapi_error(I18n.t('auth.error.token_invalid'), 'invalid_token', 403, meta: { token: token }) and return
  end

end
