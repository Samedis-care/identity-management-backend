class Api::V1::User::AccountActivityController < Api::V1::JsonApiController
  MODEL_BASE = AccountActivity
  MODEL = AccountActivity
  MODEL_OVERVIEW = AccountActivity
  SERIALIZER = AccountActivitySerializer
  OVERVIEW_SERIALIZER = AccountActivitySerializer

  SWAGGER = {
    tag: 'Current User'
  }

  undef_method :destroy
  undef_method :create
  undef_method :show

  private
  def model_index
    # leave out currently valid tokens from activities
    current_user.account_activities
                .not.where(token_id: current_user.active_logins.pluck(:id))
                .order(created_at: -1)
  end

  def cando
    CANDO.merge({
      all: %w(public) # no CANDO required to edit own user info
    })
  end

end
