class Api::V1::Apps::Tenants::Picker::UserOrganizationController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    Actor.available.groups_and_ous.where(parent_ids: current_tenant_actor.id)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = ActorSerializer
  OVERVIEW_SERIALIZER = ActorOverviewSerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  def cando
    CANDO.merge({
      index:   %w(~/app-tenant.admin ~/tenant.admin),
      show:    %w(~/app-tenant.admin ~/tenant.admin)
    })
  end

end
