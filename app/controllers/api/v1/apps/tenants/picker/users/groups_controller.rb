class Api::V1::Apps::Tenants::Picker::Users::GroupsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::Group
  MODEL = -> {
    current_tenant_actor.descendants.groups.available
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = PickerUserGroupSerializer
  OVERVIEW_SERIALIZER = PickerUserGroupSerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  def serializer_params
    super.merge({ group_ids_assigned_to_user: group_ids_assigned_to_user })
  end

  def group_ids_assigned_to_user
    @group_ids_assigned_to_user ||= begin
                                     if action_name.eql?('index')
                                       Actors::Mapping.where(
                                         user_id: params[:user_id],
                                         :parent_id.in => records_index_paged_to_a.pluck(:_id)
                                       ).distinct(:parent_id)
                                     elsif action_name.eql?('show')
                                       Actors::Mapping.where(
                                         parent_id: params[:id],
                                         user_id: params[:user_id]
                                       ).distinct(:parent_id)
                                     end
                                   end
  end

  def cando
    CANDO.merge({
                  index:   %w(~/apps.admin+identity-management/actors.reader),
                  show:    %w(~/apps.admin+identity-management/actors.reader)
                })
  end

end
