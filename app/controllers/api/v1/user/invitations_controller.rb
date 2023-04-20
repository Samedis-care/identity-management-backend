# Accept Invites for the current user
class Api::V1::User::InvitationsController < Api::V1::JsonApiController

  MODEL_BASE = Invite
  MODEL = Invite.valid
  MODEL_OVERVIEW = Invite.valid
  SERIALIZER = InvitationSerializer
  OVERVIEW_SERIALIZER = InvitationOverviewSerializer

  SWAGGER = {
    tag: 'Current User'
  }

  undef_method :index
  undef_method :show

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
  def record_destroy
    model_destroy.where(token: params_json_api[:id])
  end

  # restrict to the current_user's invites
  def model_update
    self.class::MODEL_OVERVIEW.valid.for_user(current_user)
  end

  def model_destroy
    self.class::MODEL
  end

  def cando
    CANDO.merge({
      index: %w(~/invites.reader),
      create: %w(~/invites.writer),
      destroy: %w(~/invites.deleter),
      update: %w(public)
    })
  end

  def params_create
    params.fetch(:data, {}).permit(
      :tenant_id, :invitable_id, :invitable_type, :auto_accept, :user_id
    )
  end

end
