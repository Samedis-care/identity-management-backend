class Api::V1::Apps::GroupsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::Group
  MODEL = -> {
    current_app_actor.descendants.groups.available.includes(:mappings, :actor_roles)
  }
  MODEL_OVERVIEW  = MODEL
  SERIALIZER = GroupActorSerializer
  OVERVIEW_SERIALIZER = GroupActorSerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/actors.reader),
      index:   %w(~/apps.admin+identity-management/actors.reader)
    })
  end

end
