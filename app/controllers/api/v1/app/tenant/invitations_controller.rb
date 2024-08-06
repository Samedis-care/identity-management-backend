class Api::V1::App::Tenant::InvitationsController < Api::V1::JsonApiController

  MODEL_BASE = Invite
  MODEL = Invite.valid
  MODEL_OVERVIEW = Invite.valid
  SERIALIZER = InvitationSerializer
  OVERVIEW_SERIALIZER = InvitationSerializer

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
      create: %w(~/access-control.writer ~/tenant.admin ~/app-tenant.admin),
      destroy: %w(~/access-control.writer ~/tenant.admin ~/app-tenant.admin)
    })
  end

  def params_create
    params.fetch(:data, {}).permit(
      :email, :user_id, :invitable_type, :invitable_id, :auto_accept, :target_url,
      {
        actions: {
          access_group_ids: [],
          access_groups: [],
          add_access_group_ids: [],
          add_access_groups: []
        }
      }
    )
  end

end
