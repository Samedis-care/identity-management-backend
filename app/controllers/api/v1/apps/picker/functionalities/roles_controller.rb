class Api::V1::Apps::Picker::Functionalities::RolesController < Api::V1::JsonApiController
  MODEL_BASE = Role
  MODEL = -> {
    current_app_actor.roles
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = PickerFunctionalityRoleSerializer
  OVERVIEW_SERIALIZER = PickerFunctionalityRoleSerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  def serializer_params
    super.merge({ role_ids_in_functionality: role_ids_in_functionality })
  end

  def role_ids_in_functionality
    @role_ids_in_functionality ||= Role.where(:functionality_ids => params[:functionality_id]).pluck(:_id)
  end

  def cando
    CANDO.merge({
                  index:   %w(~/apps.admin+identity-management/roles.reader+identity-management/functionalities.reader),
                  show:    %w(~/apps.admin+identity-management/roles.reader+identity-management/functionalities.reader)
                })
  end

end
