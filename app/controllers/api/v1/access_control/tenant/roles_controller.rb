class Api::V1::AccessControl::Tenant::RolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    current_app_actor.roles.available
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

  def cando
    CANDO.merge({
                  index: %w(samedis-care/access-control.reader),
                  show: %w(samedis-care/access-control.reader)
                })
  end

end
