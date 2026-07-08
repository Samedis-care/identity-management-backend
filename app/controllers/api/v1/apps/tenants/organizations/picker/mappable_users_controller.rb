class Api::V1::Apps::Tenants::Organizations::Picker::MappableUsersController < Api::V1::JsonApiController

  MODEL_BASE = Actors::User
  MODEL = -> {
    # current_app_actor.container_users.children
    Actor.user_container.children
         .set_field_map(email: :name)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = MappableUserOverviewSerializer
  OVERVIEW_SERIALIZER = SERIALIZER

  SWAGGER = { tag: 'Tenant Org Picker: Mappable Users', name: 'Mappable User', header: 'Users available for mapping to an organization' }

  undef_method :show
  undef_method :create
  undef_method :update
  undef_method :destroy

  private
  def serializer_params
    super.merge({
      actor_ids_in_orga: actor_ids_in_orga
    })
  end

  def actor_ids_in_orga
    @actor_ids_in_orga ||= begin
      if action_name.eql?('index')
        Actor.where(
          parent_id: params[:organization_id],
          :map_actor_id.in => records_index_paged_to_a.pluck(:_id)
        ).distinct(:map_actor_id)
      end
    end
  end

  # SECURITY (pen-test 2026-07): internal-admin-only. ~/tenant.admin intentionally
  # excluded — it is a per-tenant customer cando; app-tenant.admin is app-wide by
  # design, so the global authorize is correct here. Do not re-add ~/tenant.admin.
  def cando
    CANDO.merge({
      index:   %w(~/app-tenant.admin)
    })
  end

end
