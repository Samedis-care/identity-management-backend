class Api::V1::Apps::RolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    current_app_actor.roles.available
  }
  MODEL_OVERVIEW  = -> {
    current_app_actor.roles.available
  }
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = RoleOverviewSerializer

  PERMIT_CREATE = [
    :title,
    :description,
    :functionality_ids => [],
    # :actor_ids => [],
    :title_translations => {},
    :description_translations => {}
  ]
  PERMIT_UPDATE = PERMIT_CREATE

  private
  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/roles.reader),
      index:   %w(~/apps.admin+identity-management/roles.reader),
      create:  %w(~/apps.admin+identity-management/roles.writer),
      update:  %w(~/apps.admin+identity-management/roles.writer),
      destroy: %w(~/apps.admin+identity-management/roles.deleter)
    })
  end

end
