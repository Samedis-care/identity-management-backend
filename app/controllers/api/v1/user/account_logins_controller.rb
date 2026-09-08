class Api::V1::User::AccountLoginsController < Api::V1::JsonApiController
  API = :public

  MODEL_BASE = Doorkeeper::AccessToken

  # #destroy resolves through MODEL, #index through MODEL_OVERVIEW (see
  # Api::V1::JsonApiController#model_destroy / #model_index). The two used to
  # differ -- MODEL_OVERVIEW only #active_logins -- because a token soft-killed by
  # logout (Api::V1::Doorkeeper::TokensController#revoke writes expires_in: -1 for
  # the token_type_hint: 'access_token' branch) is no longer an active session, and
  # #2422 wanted it out of "active sessions". But its refresh_token deliberately
  # survives logout, because that is what powers the remembered-account fast path on
  # the login page, and from a DIFFERENT device ("forget account" only reaches the
  # browser holding the credential) the list was the only way to reach that id and
  # revoke it (#2495). So both now resolve the same unrevoked set; the serializer's
  # `active` attribute is what keeps a logged-out-but-remembered entry from being
  # mislabelled as an active session in the UI. Scoped to current_user.oauth_tokens
  # throughout, so this widens nothing across users.
  MODEL = -> {
    current_user.oauth_tokens.where(revoked_at: nil).order(created_at: -1)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = AccountLoginSerializer
  OVERVIEW_SERIALIZER = AccountLoginSerializer

  SWAGGER = {
    tag: 'Account Logins',
    name: 'Account Login',
    header: 'Login history and active sessions',
    destroy: 'Delete Access Token (logout)'
  }

  undef_method :create
  undef_method :update
  undef_method :show

  private

  def serializer_params
    @serializer_params ||= begin
      # supply bearer token to mark current active token
      { bearer_token: bearer_token }.merge super
    end
  end

  def cando
    CANDO.merge({
      all: %w(public) # no CANDO required to edit own user info
    })
  end

end
