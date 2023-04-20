class Api::V1::Apps::Tenants::Users::RolesController < Api::V1::Apps::Users::UserController

  MODEL_BASE = Role
  MODEL = -> {
    Role.available.where(actors_app: current_app_actor, :_id.in => target_user.actor.global_role_ids)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = RoleOverviewSerializer

  PERMIT_UPDATE = []

  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  def cando
    CANDO.merge({
                  show:    %w(~/app-tenant.admin ~/tenant.admin),
                  index:   %w(~/app-tenant.admin ~/tenant.admin)
                })
  end

end
