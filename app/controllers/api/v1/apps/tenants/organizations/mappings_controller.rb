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

  SWAGGER = {
    tag: 'Tenant Org Mappings',
    name: 'Mapping',
    header: 'User-to-organization mappings within a tenant'
  }.freeze

  # SECURITY / pen-test note (2026-07):
  # Admin-only endpoint. Gated to ~/app-tenant.admin, which is an APP-WIDE
  # (cross-tenant) admin cando by design — the global `authorize` is correct.
  # ~/tenant.admin was deliberately REMOVED (it is a per-tenant cando bundled
  # into ordinary customer roles) to prevent a per-tenant admin from mapping
  # actors into arbitrary tenant groups. Do not re-add ~/tenant.admin.
  # create/destroy run through the scoped MODEL (Actors::Mapping.where(parent:
  # _parent)), where _parent is resolved within this tenant's org subtree, so
  # the mapping target group is already tenant-scoped.

  undef_method :update

  private
  def json_api_permits
    super+[:organization_id]
  end

  def cando
    CANDO.merge({
      show:    %w(~/app-tenant.admin),
      index:   %w(~/app-tenant.admin),
      create:  %w(~/app-tenant.admin),
      destroy: %w(~/app-tenant.admin)
    })
  end

end
