class Api::V1::Apps::Tenants::OrganizationsTreeController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    current_tenant_actor.organization.descendants.groups_and_ous.available.find(params_json_api[:id]).children.available
  }
  MODEL_OVERVIEW  = -> {
    current_tenant_actor.organization.children.available
  }
  SERIALIZER = ActorOrganizationSerializer
  OVERVIEW_SERIALIZER = ActorOrganizationSerializer

  PERMIT_UPDATE = [:name, :short_name, :full_name, title_translations: I18n.available_locales]
  PERMIT_CREATE = [:name, :short_name, :full_name, :actor_type, :parent_id, title_translations: I18n.available_locales]

  # to render multiple (all children)
  # instead of the actual record for tree-like navigation
  def show
    render_serialized_records(
      records: model_show,
      total: model_show.count
    )
  end

  private
  def model_create
    case params_create[:actor_type].to_sym
    when :group
      Actors::Group
    when :ou
      Actors::Ou
    end
  end

  def json_api_permits
    super+[:organization_id]
  end

  def cando
    CANDO.merge({
      show:    %w(~/app-tenant.admin ~/tenant.admin),
      index:   %w(~/app-tenant.admin ~/tenant.admin)
    })
  end

end
