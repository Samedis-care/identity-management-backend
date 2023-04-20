class Api::V1::Apps::Picker::Roles::FunctionalitiesController < Api::V1::JsonApiController
  MODEL_BASE = Functionality
  MODEL = -> {
    current_app_actor.functionalities
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = PickerRoleFunctionalitySerializer
  OVERVIEW_SERIALIZER = PickerRoleFunctionalitySerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  def serializer_params
    super.merge({ functionality_ids_in_role: functionality_ids_in_role })
  end

  def functionality_ids_in_role
    @functionality_ids_in_role ||= begin
                             if action_name.eql?('index')
                               RoleFunctionality.where(
                                 role_id: params[:role_id],
                                 :functionality_id.in => records_index_paged_to_a.pluck(:_id)
                               ).distinct(:functionality_id)
                             elsif action_name.eql?('show')
                               RoleFunctionality.where(
                                 role_id: params[:role_id],
                                 functionality_id: params[:id]
                               ).distinct(:functionality_id)
                             end
                           end
  end

  def cando
    CANDO.merge({
                  index:   %w(~/apps.admin+identity-management/functionalities.reader+identity-management/roles.reader),
                  show:    %w(~/apps.admin+identity-management/functionalities.reader+identity-management/roles.reader)
                })
  end

end
