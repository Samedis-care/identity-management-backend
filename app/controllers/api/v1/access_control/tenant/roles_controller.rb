class Api::V1::AccessControl::Tenant::RolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    current_app_actor.roles.where(:_id.in => tenant_role_ids).available
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = RolePickerSerializer
  OVERVIEW_SERIALIZER = RolePickerSerializer

  PERMIT_CREATE = [].freeze
  PERMIT_UPDATE = PERMIT_CREATE

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  # ensures the roles returned are reduced
  # to only those that the current_tenant has available
  # within the organization structure (as defined by app orga)
  # this is critical to avoid exposing highly privileged
  # administative roles
  def tenant_role_ids
    @tenant_role_ids ||= current_tenant_actor.available_role_ids
  end

  def cando
    CANDO.merge({
                  index: %w(samedis-care/access-control.reader),
                  show: %w(samedis-care/access-control.reader)
                })
  end

end
