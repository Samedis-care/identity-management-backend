class Api::V1::User::TenantsController < Api::V1::JsonApiController
  API = :internal

  MODEL_BASE = Actors::Tenant
  MODEL = ::Actors::Tenant.available
  MODEL_OVERVIEW = ::Actors::Tenant.available
  SERIALIZER = ActorSerializer
  OVERVIEW_SERIALIZER = ActorOverviewSerializer

  SWAGGER = {
    tag: 'My Tenants',
    name: 'My Tenant',
    header: 'Tenants the current user is a member of',
    action_suffix: 'of the current user'
  }

  private
  # restrict to the current_user's tenant(s): only a genuine app-wide admin
  # (holding app-tenant.admin in one of their tenants) may see all tenants;
  # everyone else is scoped to their own memberships.
  #
  # SECURITY (pen-test 2026-07, cross-tenant enumeration): the previous guard
  # relied on cando_any_for_tenants? in a boolean context while that method
  # returned an Array (always truthy) and was passed a String — so it returned
  # every tenant on the platform to any authenticated user. cando_any_for_tenants?
  # is now a real predicate (see JsonApiController).
  def model_index
    if cando_any_for_tenants?("#{current_app}/app-tenant.admin")
      self.class::MODEL_OVERVIEW
    else
      self.class::MODEL_OVERVIEW.where(:id.in => current_user.actor.actor_ids)
    end
  end
  def model_show
    model_index
  end
  def model_create
    self.class::MODEL
  end
  def model_update
    model_index
  end
  def model_destroy
    model_index
  end

  def record_show
    model_show.find(params_json_api[:id])
  end
  def record_update
    model_update.find(params_json_api[:id])
  end
  def record_destroy
    model_destroy.find(params_json_api[:id])
  end

  def params_update
    params.fetch(:data, {}).permit(:image_b64, :image, :short_name, :full_name)
  end
  def params_create
    params_update.merge(parent: current_app_container_tenants, owner: current_user.actor)
  end

  def cando
    CANDO.merge({
      index: %w(public),
      create: %w(public),
      show: %w(public),
      update: %W(identity-management/actors.writer ~/app-tenant.admin ~/tenant.admin),
      destroy: %W(identity-management/actors.writer ~/app-tenant.admin ~/tenant.admin)
    })
  end

end
