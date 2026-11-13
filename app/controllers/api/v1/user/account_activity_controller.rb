class Api::V1::User::AccountActivityController < Api::V1::JsonApiController
  API = :internal
  MODEL_BASE = AccountActivity
  MODEL = AccountActivity
  MODEL_OVERVIEW = AccountActivity
  SERIALIZER = AccountActivitySerializer
  OVERVIEW_SERIALIZER = AccountActivitySerializer

  SWAGGER = {
    tag: 'Current User',
    name: 'Account Activity',
    header: 'Activity log of the current user account'
  }

  undef_method :destroy
  undef_method :create
  undef_method :show

  private
  def model_index
    # Lists every login activity, including those of still active sessions (and the
    # current one). Active sessions also show up in AccountLoginsController; appearing
    # in both lists is intended (samedis-care-issues#3635).
    current_user.account_activities.order(created_at: -1)
  end

  def cando
    CANDO.merge({
      all: %w(public) # no CANDO required to edit own user info
    })
  end

end
