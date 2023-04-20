class Api::V1::Apps::Tenants::Organizations::MappingsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::Mapping
  MODEL = -> {
    _parent = current_app_actor.tenants.find(params_json_api[:tenant_id])
      .organization.descendants.groups.available
      .find(params_json_api[:organization_id])
    Actors::Mapping.where(parent: _parent)
  }
  MODEL_OVERVIEW  = MODEL
  SERIALIZER = MappingSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_CREATE = [:map_actor_id, :user_id]

  undef_method :update

  private
  def json_api_permits
    super+[:organization_id]
  end

  def cando
    CANDO.merge({
      show:    %w(~/app-tenant.admin ~/tenant.admin),
      index:   %w(~/app-tenant.admin ~/tenant.admin),
      create:  %w(~/app-tenant.admin ~/tenant.admin),
      destroy: %w(~/app-tenant.admin ~/tenant.admin)
    })
  end

end
