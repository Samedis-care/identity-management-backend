class Api::V1::Apps::Users::TenantsController < Api::V1::Apps::Users::UserController

  MODEL_BASE = Actors::Tenant
  MODEL = -> {
    current_app_actor.tenants.available.where(:id.in => target_user.actor.actor_ids)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = TenantSerializer
  OVERVIEW_SERIALIZER = TenantSerializer

  PERMIT_UPDATE = []

  SWAGGER = {
    action_suffix: 'a User has in an App'
  }

  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  def cando
    CANDO.merge({
                  show:    %w(~/apps.admin+identity-management/actors.reader),
                  index:   %w(~/apps.admin+identity-management/actors.reader)
                })
  end

end
