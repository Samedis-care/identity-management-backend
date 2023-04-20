class Api::V1::Apps::Tenants::Users::ActorsController < Api::V1::Apps::Users::UserController

  MODEL_BASE = Actors::Mapping
  MODEL = -> {
    current_app_actor.tenants.find(params_json_api[:tenant_id]).descendants.where(:id.in => mappings.distinct(:parent_id))
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
      map_actor_id: target_user.actor_id,
      tenant_id: params_json_api[:tenant_id]
    )
  end

  def mappings
    @mappings ||= Actors::Mapping.where(parent_ids: BSON::ObjectId(current_path_tenant_id), map_actor_id: target_user.actor_id)
  end

  def serializer_params
    @serializer_params ||= {
      mappings: mappings.map { |r| [r.parent_id, r] }.to_h
    }
  end

  def cando
    CANDO.merge({
                  show:    %w(~/app-tenant.admin ~/tenant.admin),
                  index:   %w(~/app-tenant.admin ~/tenant.admin),
                  create:  %w(~/app-tenant.admin ~/tenant.admin),
                  destroy: %w(~/app-tenant.admin ~/tenant.admin),
                })
  end

end
