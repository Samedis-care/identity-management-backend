class Api::V1::Apps::Tenants::Organizations::ActorRolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    current_app_actor.tenants.find(params_json_api[:tenant_id])
      .organization.descendants.groups.available
      .find(params_json_api[:organization_id]).roles
  }
  MODEL_OVERVIEW  = MODEL
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_CREATE = [:role_id]

  SWAGGER = {
    tag: 'Tenant Org Roles',
    name: 'Organization Role',
    header: 'Manage roles within a tenant organization'
  }

  # SECURITY / pen-test note (2026-07):
  # Admin-only endpoint. Access is intentionally gated to ~/app-tenant.admin,
  # which is an APP-WIDE (cross-tenant) admin cando by design — hence the global
  # `authorize` (not tenant_authorize) is correct here.
  # ~/tenant.admin was deliberately REMOVED from the cando list: it is a
  # per-tenant cando bundled into ordinary customer roles (e.g. "Edit facility
  # data"), and combined with the global cando check it let a plain tenant admin
  # assign themselves privileged roles (incl. apps.admin) -> privilege
  # escalation. Do not re-add ~/tenant.admin here.
  # NOTE: an app-tenant.admin can still assign any app role to any actor
  # (Actor.find/role lookups are unscoped); that is accepted as a trusted-admin
  # capability. Keep app-tenant.admin restricted to trusted operators.

  undef_method :update

  def create
    record = actor
    record.role_ids << role.id
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record(
      record: role
    )
  end

  def destroy
    actors.each do |actor|
      actor.role_ids.delete(BSON::ObjectId(params_json_api[:id]))
      actor.save!
    end
    render_jsonapi_msg({
      success: true,
      error: nil,
      message: nil,
      error_details: nil
    })
  end

  private

  def actor
    @actor ||= Actor.find(params[:organization_id])
  end

  def actors
    @actors ||= Actor.find(ApplicationDocument.ensure_bson(params[:organization_id]))
  end

  def role
    @role ||= current_app_actor.roles.find(params_create[:role_id])
  end

  private
  def json_api_permits
    super+[:organization_id, :role_id]
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
