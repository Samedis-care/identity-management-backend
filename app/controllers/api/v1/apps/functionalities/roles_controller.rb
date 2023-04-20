# compatablity controller to allow frontend endpoints to work
class Api::V1::Apps::Functionalities::RolesController < Api::V1::JsonApiController

  MODEL_BASE = Role
  MODEL = -> {
    Role.where(functionality_ids: params[:functionality_id])
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = RoleSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_CREATE = [:role_id]

  undef_method :update

  def create
    record = role
    record.functionality_ids << functionality.id
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record(
      record: role
    )
  end

  def destroy
    roles.each do |role|
      role.functionality_ids.delete(functionality.id)
      role.save!
    end
    render_jsonapi_msg({
      success: true,
      error: nil,
      message: nil,
      error_details: nil
    })
  end

  private

  def roles
    @roles ||= Role.find(ApplicationDocument.ensure_bson(params[:id]))
  end

  def role
    @role ||= Role.find(params_create[:role_id])
  end

  def functionality
    current_app_actor.functionalities.find(params[:functionality_id])
  end

  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/roles.reader),
      index:   %w(~/apps.admin+identity-management/roles.reader),
      create:  %w(~/apps.admin+identity-management/roles.writer),
      destroy: %w(~/apps.admin+identity-management/roles.writer)
    })
  end

end
