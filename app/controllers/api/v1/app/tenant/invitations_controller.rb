class Api::V1::App::Tenant::InvitationsController < Api::V1::JsonApiController

  MODEL_BASE = Invite
  MODEL = Invite.valid
  MODEL_OVERVIEW = Invite.valid
  SERIALIZER = InvitationSerializer
  OVERVIEW_SERIALIZER = InvitationSerializer

  # Samedis-care/samedis-care-issues#2811: declaring this instead of
  # overriding #params_create makes the request body's OpenAPI schema get generated from
  # this list (JsonApiController#permitted_attributes_for_create ->
  # InvitationSerializer::Schema#openapi_consumes_schema) instead of falling back to
  # "does not support sending any attributes" - which was still true for valid_until after
  # just exposing it in the response half. #params_create's base implementation
  # (params.fetch(:data, {}).permit(*self.class::PERMIT_CREATE)) is behaviourally identical
  # to the override this replaces.
  PERMIT_CREATE = [
    :email, :user_id, :invitable_type, :invitable_id, :auto_accept, :target_url, :valid_until,
    {
      actions: {
        access_group_ids: [],
        access_groups: [],
        add_access_group_ids: [],
        add_access_groups: []
      }
    }
  ].freeze

  SWAGGER = { tag: 'Tenant Invitations', name: 'Invitation', header: 'Manage tenant invitations for an app' }

  undef_method :index
  undef_method :show
  undef_method :update

  def create
    super do |record, opts|
      opts[:meta] ||= {}
      opts[:meta][:access_groups] = ::AccessControl.for_tenant(current_tenant_id)
      [record, opts]
    end
  end

  private

  def record_create
    model_create.create(params_create.merge(app: current_app, tenant_id: current_tenant_id))
  end

  def records_destroy
    ids = params_json_api[:id].to_s.gsub(',', ' ').split(' ')
    model_destroy.where(:token.in => ids)
  end

  def cando
    CANDO.merge({
      create:  %w(~/invitations.writer ~/access-control.writer ~/tenant.admin ~/app-tenant.admin),
      destroy: %w(~/invitations.writer ~/tenant.admin ~/app-tenant.admin)
    })
  end

end
