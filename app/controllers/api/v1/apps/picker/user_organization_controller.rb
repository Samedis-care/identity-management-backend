class Api::V1::Apps::Picker::UserOrganizationController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    Actor.available.groups_and_ous.where(parent_ids: BSON::ObjectId(current_app_id))
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = ActorSerializer
  OVERVIEW_SERIALIZER = ActorOverviewSerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  def cando
    CANDO.merge({
      index:   %w(~/apps.admin+identity-management/actors.reader),
      show:    %w(~/apps.admin+identity-management/actors.reader)
    })
  end

end
