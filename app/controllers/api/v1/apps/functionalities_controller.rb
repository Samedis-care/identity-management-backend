class Api::V1::Apps::FunctionalitiesController < Api::V1::JsonApiController

  MODEL_BASE = Functionality
  MODEL = -> {
    current_app_actor.functionalities.available
  }
  MODEL_OVERVIEW  = -> {
    current_app_actor.functionalities.available
  }
  SERIALIZER = FunctionalitySerializer
  OVERVIEW_SERIALIZER = FunctionalityOverviewSerializer

  PERMIT_UPDATE = [
    :title,
    :description,
    :module, :ident,
    :role_ids => [],
    :title_translations => {},
    :description_translations => {}
  ]
  PERMIT_CREATE = PERMIT_UPDATE

  private
  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/functionalities.reader),
      index:   %w(~/apps.admin+identity-management/functionalities.reader),
      create:  %w(~/apps.admin+identity-management/functionalities.writer),
      update:  %w(~/apps.admin+identity-management/functionalities.writer),
      destroy: %w(~/apps.admin+identity-management/functionalities.deleter)
    })
  end

end
