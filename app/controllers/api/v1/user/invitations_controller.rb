# Accept Invites for the current user
class Api::V1::User::InvitationsController < Api::V1::JsonApiController
  API = :internal

  MODEL_BASE = Invite
  MODEL = Invite.valid
  MODEL_OVERVIEW = Invite.valid
  SERIALIZER = InvitationSerializer
  OVERVIEW_SERIALIZER = InvitationOverviewSerializer

  SWAGGER = {
    tag: 'Current User',
    name: 'My Invitation',
    header: 'Pending invitations for the current user'
  }

  # only the noswagger accept PUT is routed
  undef_method :create
  undef_method :index
  undef_method :show
  undef_method :destroy

  def update
    records = model_update.where(token: params_json_api[:id])
    records.each do |invite|
      invite.accept!
    end
    render_serialized_records(
      records: records
    )
  end

  private
  # restrict to the current_user's invites
  def model_update
    self.class::MODEL_OVERVIEW.valid.for_user(current_user)
  end

  # Accepting needs no cando: model_update limits it to the current user's own
  # invites. The ~/invites.* candos once listed here guarded actions this
  # controller never served (Samedis-care/samedis-care-issues#2658).
  def cando
    CANDO.merge({
      update: %w(public)
    })
  end

end
