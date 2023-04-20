class Api::V1::Apps::OrganizationsController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    current_app_actor.organization.descendants.available
  }
  MODEL_OVERVIEW  = MODEL
  SERIALIZER = ActorOrganizationSerializer
  OVERVIEW_SERIALIZER = ActorOrganizationSerializer

  PERMIT_UPDATE = [
    :short_name,
    :full_name,
    :title,
    :title_translations => {}
  ]
  PERMIT_CREATE = [
    :parent_id,
    :name,
    :short_name,
    :full_name,
    :actor_type,
    :title,
    :title_translations => {},
  ]

  private
  def model_create
    begin
      "Actors::#{params_create[:actor_type].camelcase}".constantize
    rescue => e
      render_generic_error(Exception.new('Invalid or missing actor_type')) and return
    end
  end

  # enforce parent to be not outside of the organization node
  def params_create
    @params_create ||= begin
      _params_create = super
      _parent = Actor.find(_params_create[:parent_id])
      unless _parent.parent_ids.include? current_app_actor.organization.id
        _params_create[:parent_id] = current_app_actor.organization.id
      end
      _params_create
    end
  end

  def json_api_permits
    super+[:organization_id]
  end

  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/actors.reader),
      index:   %w(~/apps.admin+identity-management/actors.reader),
      create:  %w(~/apps.admin+identity-management/actors.writer),
      update:  %w(~/apps.admin+identity-management/actors.writer),
      destroy: %w(~/apps.admin+identity-management/actors.deleter)
    })
  end

end
