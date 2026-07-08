class Api::V1::Apps::Tenants::Users::RolesController < Api::V1::Apps::Users::UserController

  MODEL_BASE = Role
  MODEL = -> {
    Role.available.where(actors_app: current_app_actor, :_id.in => target_user.actor.global_role_ids)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = RoleOverviewSerializer

  PERMIT_UPDATE = []

  SWAGGER = { tag: 'Tenant User Roles', name: 'Role', header: 'Roles assigned to a tenant user' }

  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  # SECURITY (pen-test 2026-07): internal-admin-only. ~/tenant.admin intentionally
  # excluded — it is a per-tenant customer cando; app-tenant.admin is app-wide by
  # design, so the global authorize is correct here. Do not re-add ~/tenant.admin.
  def cando
    CANDO.merge({
                  show:    %w(~/app-tenant.admin),
                  index:   %w(~/app-tenant.admin)
                })
  end

end
