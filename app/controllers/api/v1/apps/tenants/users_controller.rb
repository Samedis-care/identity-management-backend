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

  # Candos from #cando that are app-wide by design and therefore also count when
  # held in any tenant, like the global `authorize` on Api::V1::Apps::UsersController
  # (App > Users, same users and update fields) and the sibling apps/tenants/*
  # endpoints. Without this an app admin who is not a member of the path tenant
  # is refused (Samedis-care/samedis-care-issues#3530).
  # Never add ~/tenant.admin: it is per-tenant and bundled into customer roles.
  APP_WIDE_CANDOS = %w(
    ~/app-tenant.admin
    ~/apps.admin+identity-management/users.reader
    ~/apps.admin+identity-management/users.writer
  ).freeze

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

  def tenant_authorization
    super || app_wide_authorization
  end

  # Checks only the APP_WIDE_CANDOS entries of the current action's requirements
  # against all of the caller's candos.
  def app_wide_authorization
    app_wide = APP_WIDE_CANDOS.map do |c|
      c.split('+').map { |s| s.sub(%r{\A~/}, "#{current_app_actor.name}/") }
    end
    requirements = current_cando_requirements.map do |combos|
      combos.select { |combo| app_wide.include?(combo) }
    end
    current_user.cando_any?(requirements) rescue false
  end

end
