class Api::V1::Apps::TenantsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::Tenant
  MODEL = -> {
    current_app_actor.tenants.available
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = TenantSerializer
  OVERVIEW_SERIALIZER = TenantSerializer

  PERMIT_UPDATE = [:short_name, :full_name, :image, :image_b64, modules_selected: []]

  SWAGGER = {
    action_suffix: 'of an App'
  }

  undef_method :create

  private
  def cando
    CANDO.merge({
      show:    %w(~/apps.admin ~/app-tenant.admin),
      index:   %w(~/apps.admin ~/app-tenant.admin),
      update:  %w(~/apps.admin ~/app-tenant.admin),
      destroy:  %w(~/apps.admin ~/app-tenant.admin)
    })
  end

end
