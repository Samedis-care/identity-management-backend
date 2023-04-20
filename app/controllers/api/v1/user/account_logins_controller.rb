class Api::V1::User::AccountLoginsController < Api::V1::JsonApiController

  MODEL_BASE = Doorkeeper::AccessToken
  MODEL = -> {
    current_user.active_logins.order(created_at: -1)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = AccountLoginSerializer
  OVERVIEW_SERIALIZER = AccountLoginSerializer

  SWAGGER = {
    tag: 'Account Logins',
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
