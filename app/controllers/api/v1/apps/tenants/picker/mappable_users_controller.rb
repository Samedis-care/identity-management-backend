class Api::V1::Apps::Tenants::Picker::MappableUsersController < Api::V1::JsonApiController

  MODEL_BASE = Actors::User
  MODEL = -> {
    # current_app_actor.container_users.children
    Actor.user_container.children
         .set_field_map(email: :name)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = MappableUserOverviewSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  SWAGGER = { tag: 'Tenant Picker: Mappable Users', name: 'Mappable User', header: 'Users available for mapping within a tenant' }

  undef_method :show
  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  # SECURITY (pen-test 2026-07): internal-admin-only. ~/tenant.admin intentionally
  # excluded — it is a per-tenant customer cando; app-tenant.admin is app-wide by
  # design, so the global authorize is correct here. Do not re-add ~/tenant.admin.
  def cando
    CANDO.merge({
      index:   %w(~/app-tenant.admin)
    })
  end

end
