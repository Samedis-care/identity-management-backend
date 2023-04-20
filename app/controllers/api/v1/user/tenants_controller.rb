class Api::V1::User::TenantsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::Tenant
  MODEL = ::Actors::Tenant.available
  MODEL_OVERVIEW = ::Actors::Tenant.available
  SERIALIZER = ActorSerializer
  OVERVIEW_SERIALIZER = ActorOverviewSerializer

  SWAGGER = {
    action_suffix: 'of the current user'
  }

  private
  # restrict to the current_user's tenant(s)
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
    model_show
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
