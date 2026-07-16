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
  # restrict to the current_user's tenant(s).
  # SECURITY (pen-test 2026-07, cross-tenant enumeration): the previous guard
  #   `if cando_any_for_tenants?("#{current_app}/app-tenant.admin")`
  # was always truthy — cando_any_for_tenants? returns an Array (every Array,
  # incl. []), and the cando was passed as a String (cando_any? returns false
  # for non-Array input), so it unconditionally returned every tenant on the
  # platform. Only genuine app-wide admins (holding app-tenant.admin for this
  # app) may see all tenants; everyone else is scoped to their own memberships.
  def model_index
    if current_user.global_candos.include?("#{current_app}/app-tenant.admin")
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
