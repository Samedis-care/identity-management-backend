class Api::V1::Apps::Tenants::UsersController < Api::V1::JsonApiController

  MODEL_BASE = User
  MODEL = -> {
    current_tenant_actor.users.available
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = AppUserSerializer
  OVERVIEW_SERIALIZER = UserOverviewSerializer

  PERMIT_UPDATE = [
    :image_b64,
    :image,
    :pwd_reset_uid,
    :active,
    :email,
    :picture,
    :locale,
    :set_password,
    :new_password,
    :new_password_verify,
    :title,
    :first_name,
    :last_name,
    :short,
    :gender,
    :invalid_at
  ]

  SWAGGER = { tag: 'Tenant Users', name: 'User', header: 'Manage users within a tenant of an app' }

  # Tenant-scoped authorization: the required cando must be held IN the target
  # tenant (current_tenant is membership-scoped). Prevents a tenant.admin of one
  # tenant from acting on users of another tenant. See security audit C-1.
  skip_before_action :authorize
  before_action :tenant_authorize

  # Candos from #cando that also count when held in any tenant, so an app admin
  # who is not a member of the path tenant is not refused
  # (Samedis-care/samedis-care-issues#3530). The apps.admin combos are the ones
  # Api::V1::Apps::UsersController (App > Users, same users and update fields)
  # checks globally. app-tenant.admin is app-wide for reading only, as on the
  # sibling apps/tenants/* endpoints: app-wide it would reach set_password of
  # every user in the app.
  # Never add ~/tenant.admin: it is per-tenant and bundled into customer roles.
  APP_WIDE_CANDOS = {
    show:   %w(~/app-tenant.admin ~/apps.admin+identity-management/users.reader),
    index:  %w(~/app-tenant.admin ~/apps.admin+identity-management/users.reader),
    update: %w(~/apps.admin+identity-management/users.writer)
  }.freeze

  undef_method :create
  undef_method :destroy

  private
  def cando
    CANDO.merge({
      show:    %w(~/app-tenant.admin ~/apps.admin+identity-management/users.reader ~/tenant.admin),
      index:   %w(~/app-tenant.admin ~/apps.admin+identity-management/users.reader ~/tenant.admin),
      update:  %w(~/app-tenant.admin ~/apps.admin+identity-management/users.writer ~/tenant.admin)
    })
  end

end
