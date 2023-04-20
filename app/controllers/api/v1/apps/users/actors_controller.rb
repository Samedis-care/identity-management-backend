class Api::V1::Apps::Users::ActorsController < Api::V1::Apps::Users::UserController

  MODEL_BASE = Actor
  MODEL = -> {
    current_app_actor.descendants.where(:id.in => mappings.distinct(:parent_id))
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = UserOrganizationSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  PERMIT_UPDATE = []

  undef_method :update

  def create
    actor = Actor.where(parent_ids: BSON::ObjectId(current_app_id)).find params_json_api.dig(:data, :actor_id)
    record = check_for_errors(actor.map_into!(target_user.actor)) #|| return
    @mappings = nil
    record.validate
    record = check_for_errors(record) || return
    record.save!
    render_serialized_record record: record
  end

  private
  def records_destroy
    ids = params_json_api[:id].to_s.gsub(',',' ').split(' ')
    Actors::Mapping.where(
      :parent_id.in => ids,
      app_id: BSON::ObjectId(current_app_id),
      map_actor_id: target_user.actor_id
    )
  end

  def mappings
    @mappings ||= Actors::Mapping.where(parent_ids: BSON::ObjectId(current_app_id), map_actor_id: target_user.actor_id)
  end

  def serializer_params
    @serializer_params ||= {
      mappings: mappings.map { |r| [r.parent_id, r] }.to_h
    }
  end

  def cando
    CANDO.merge({
                  show:    %w(~/apps.admin+identity-management/users.reader+identity-management/actors.reader),
                  index:   %w(~/apps.admin+identity-management/users.reader+identity-management/actors.reader),
                  create:  %w(~/apps.admin+identity-management/users.reader+identity-management/actors.writer),
                  destroy: %w(~/apps.admin+identity-management/users.reader+identity-management/actors.writer),
                })
  end

end
