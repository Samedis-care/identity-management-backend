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

  undef_method :show
  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  def cando
    CANDO.merge({
      index:   %w(~/app-tenant.admin ~/tenant.admin)
    })
  end

end
