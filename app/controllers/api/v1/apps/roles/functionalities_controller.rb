# compatablity controller to allow frontend endpoints to work
class Api::V1::Apps::Roles::FunctionalitiesController < Api::V1::JsonApiController

  MODEL_BASE = Functionality
  MODEL = -> {
    role.functionalities
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = FunctionalitySerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_CREATE = [:functionality_id]

  undef_method :update

  def create
    record = role
    record.functionality_ids << functionality.id
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record(
      record: functionality
    )
  end

  def destroy
    record = role
    ApplicationDocument.ensure_bson(params[:id]).each do |_id|
      record.functionality_ids.delete(_id)
    end
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_jsonapi_msg({
      success: true,
      error: nil,
      message: nil,
      error_details: nil
    })
  end

  private

  def functionality
    @functionality ||= Functionality.find(params_create[:functionality_id])
  end

  def role
    current_app_actor.roles.find(params[:role_id])
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
