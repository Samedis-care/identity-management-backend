class Api::V1::Apps::OrganizationsTreeController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    current_app_actor.organization.descendants.groups_and_ous.available.find(params_json_api[:id]).children.available
  }
  MODEL_OVERVIEW  = -> {
    current_app_actor.organization.children.available
  }
  SERIALIZER = ActorOrganizationSerializer
  OVERVIEW_SERIALIZER = ActorOrganizationSerializer

  PERMIT_UPDATE = [:short_name, :full_name]
  PERMIT_CREATE = [:short_name, :full_name, :actor_type]

  def index(&block)
    if !Rails.env.production? and params[:format].eql? 'html'
      # open this with the URL /api/v1/apps/:app_id/organizations_tree.html?bearer_token=BEARER_TOKEN&include_mappings=false
      # options:
      # - parameter name - data type - default value - description
      # - include_mappings - boolean - false - Show mappings in tree?
      render 'debug/actor_tree', locals: {
        app: current_app_actor,
        cfg: params.permit(:include_mappings).to_h.freeze
      } and return
    end
    super
  end

  # to render multiple (all children)
  # instead of the actual record for tree-like navigation
  def show
    render_serialized_records(
      records: model_show,
      total: model_show.count
    )
  end

  private
  def json_api_permits
    super+[:organization_id]
  end

  def cando
    CANDO.merge({
      show:           %w(~/apps.admin+identity-management/actors.reader),
      index:          %w(~/apps.admin+identity-management/actors.reader),
      'index.html':   %w(identity-management/actors.reader)
    })
  end

end
