class Api::V1::Apps::Picker::Roles::UserOrganizationController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    Actor.available.groups_and_ous.where(parent_ids: BSON::ObjectId(current_app_id))
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = PickerRoleActorSerializer
  OVERVIEW_SERIALIZER = PickerRoleActorSerializer

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  def serializer_params
    super.merge({
      actor_ids_in_role: actor_ids_in_role
    })
  end

  def actor_ids_in_role
    @actor_ids_in_role ||= begin
      if action_name.eql?('index')
        Actor.where(
          role_ids: params[:role_id],
          :_id.in => records_index_paged_to_a.pluck(:_id)
        ).distinct(:_id)
      elsif action_name.eql?('show')
        Actor.where(
          role_ids: params[:role_id],
          _id: params[:id]
        ).distinct(:_id)
      end
    end
  end

  def cando
    CANDO.merge({
      index:   %w(~/apps.admin+identity-management/actors.reader+identity-management/roles.reader),
      show:    %w(~/apps.admin+identity-management/actors.reader+identity-management/roles.reader)
    })
  end

end
