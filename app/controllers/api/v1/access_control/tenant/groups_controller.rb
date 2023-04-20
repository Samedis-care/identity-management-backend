class Api::V1::AccessControl::Tenant::GroupsController < Api::V1::JsonApiController

  skip_before_action :authorize
  before_action :tenant_authorize

  PAGE_LIMIT = 100
  PAGE_LIMIT_MAX = 100

  MODEL_BASE = AccessControl
  MODEL = ::AccessControl
  MODEL_OVERVIEW = ::AccessControl
  SERIALIZER = AccessControlSerializer
  OVERVIEW_SERIALIZER = AccessControlSerializer

  SWAGGER = {
    tag: 'Access Control',
    action_suffix: 'available groups of this tenant'
  }

  undef_method :update
  undef_method :create
  undef_method :show
  undef_method :destroy

  def index
    determine = self.class::MODEL.for_tenant(tenant_id)
    respond_to do |format|
      format.any {
        render_serialized_records(
          records: determine,
          total: determine.count
        )
      }
    end
  end

  private

  # return the tenant_id from filter[tenant_id] if the current_user is member of that tenant
  def tenant_id
    (current_user.tenants.pluck(:id) & [params_json_api[:tenant_id]]).first || raise("MISSING_TENANT_ID")
  end

  def json_api_permits
    super + [:tenant_id]
  end

  def cando
    CANDO.merge({
      index:  %w(~/access-control.reader)
    })
  end

end
