# compatablity controller to allow frontend endpoints to work
class Api::V1::Apps::Roles::ActorRolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    role.actors
  }
  MODEL_OVERVIEW  = MODEL
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_CREATE = [:actor_id]

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
      actor.role_ids.delete(role.id)
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
    @actor ||= Actor.find(params_create[:actor_id])
  end

  def actors
    @actors ||= Actor.find(ApplicationDocument.ensure_bson(params[:id]))
  end

  def role
    @role ||= current_app_actor.roles.find(params[:role_id])
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
