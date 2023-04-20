class Api::V1::Apps::Tenants::OrganizationsController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    current_tenant_actor.organization.descendants.available
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = ActorOrganizationSerializer
  OVERVIEW_SERIALIZER = ActorOrganizationSerializer

  PERMIT_UPDATE = [:name, :short_name, :full_name, title_translations: I18n.available_locales]
  PERMIT_CREATE = [:name, :short_name, :full_name, :actor_type, :parent_id, title_translations: I18n.available_locales]

  private
  def model_create
    case params_create[:actor_type]&.to_sym
    when :group
      Actors::Group
    when :ou
      Actors::Ou
    else
      render_generic_error(Exception.new('Invalid or missing actor_type')) and return
    end
  end

  # enforce parent to be not outside of the organization node
  def params_create
    @params_create ||= begin
      _params_create = super
      _parent = Actor.find(_params_create[:parent_id])
      unless _parent.parent_ids.include? current_tenant_actor.organization.id
        _params_create[:parent_id] = current_tenant_actor.organization.id
      end
      _params_create
    end
  end

  def json_api_permits
    super+[:organization_id]
  end

  def cando
    CANDO.merge({
      show:    %w(~/app-tenant.admin ~/tenant.admin),
      index:   %w(~/app-tenant.admin ~/tenant.admin),
      create:  %w(~/app-tenant.admin ~/tenant.admin),
      update:  %w(~/app-tenant.admin ~/tenant.admin),
      destroy: %w(~/app-tenant.admin ~/tenant.admin)
    })
  end

end
