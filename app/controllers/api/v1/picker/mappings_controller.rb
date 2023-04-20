class Api::V1::Picker::MappingsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::Mapping
  MODEL = -> {
    Actor.user_container
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = ActorMappingsSerializer
  OVERVIEW_SERIALIZER = ActorMappingsSerializer

  undef_method :show
  undef_method :create
  undef_method :update
  undef_method :destroy

  # This is for pickers to select actors to be
  # newly mapped into the given :actor_id
  def index
    actor = Actor.available.find(params_json_api[:actor_id])
    determine = Actor.get_mappings(actor, params_json_api.dig(:filter, :mapped))
                     .quickfilter(params_json_api[:quickfilter]||params_json_api[:query])
                     .gridfilter(params_json_api[:gridfilter])

    records = determine.sorting(params_json_api[:sort]).paginate(per_page: json_api_options[:limit], page: json_api_options[:page])
    render_serialized_records(
      records: records,
      total: determine.count
    ) do |records, opts|
      mappings = actor.children.mappings
                 .where(:map_actor_id.in => records.distinct(:_id))
                 .distinct(:map_actor_id)
      records = records.map do |r|
        unless r.is_mapping?
          r.mapped = mappings.include?(r.id)
        end
        r
      end
      [records,opts]
    end
  end

  private
  def json_api_permits
    super+[:actor_id]
  end

  def cando
    CANDO.merge({
      index:   %w(identity-management/actors.reader),
      show:    %w(identity-management/actors.reader)
    })
  end

end
