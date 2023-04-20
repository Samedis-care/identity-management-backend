class Api::V1::Apps::Organizations::ActorRolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    current_app_actor.organization.descendants
      .groups.available.find(params_json_api[:organization_id]).roles
  }
  MODEL_OVERVIEW  = MODEL
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_CREATE = [:role_id]

  undef_method :update


  def create
    record = actor
    record.role_ids << role.id
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record(
      record: role
    )
  end

  def destroy
    actors.each do |actor|
      actor.role_ids.delete(BSON::ObjectId(params_json_api[:id]))
      actor.save!
    end
    render_jsonapi_msg({
      success: true,
      error: nil,
      message: nil,
      error_details: nil
    })
  end

  private

  def actor
    @actor ||= Actor.find(params[:organization_id])
  end

  def actors
    @actors ||= Actor.find(ApplicationDocument.ensure_bson(params[:organization_id]))
  end

  def role
    @role ||= current_app_actor.roles.find(params_create[:role_id])
  end

  def json_api_permits
    super+[:organization_id, :role_id]
  end

  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/actors.reader),
      index:   %w(~/apps.admin+identity-management/actors.reader),
      create:  %w(~/apps.admin+identity-management/actors.writer),
      destroy: %w(~/apps.admin+identity-management/actors.writer)
    })
  end

end
