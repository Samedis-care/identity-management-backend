class Api::V1::Picker::TenantUsersController < Api::V1::JsonApiController

  MODEL_BASE = User
  MODEL = User.available
  MODEL_OVERVIEW = User.available
  SERIALIZER = TenantUserSerializer
  OVERVIEW_SERIALIZER = TenantUserOverviewSerializer

  PARAM_UPDATE = [tenant_groups: []]

  undef_method :create
  undef_method :destroy

  def update
    user = User.available.find(params_json_api[:id])
    actor = user.actor
    tenant = Actor.tenants.find(tenant_id)
    tenant_groups_available = tenant.defaults[:children].pluck(:name)
    tenant_groups_selected = params_json_api.dig(:data, :tenant_groups)
    tenant_groups_available.each do |group_name|
      group = tenant.children.groups.where(name: group_name).first
      if tenant_groups_selected.include?(group_name)
        group.map_into!(actor)
      else
        group.unmap_from!(actor)
      end
    end

    render_serialized_record(
      record: user.reload
    )
  end

  private
  def model_index
    self.class::MODEL_OVERVIEW.of_tenant_id(tenant_id)
  end
  def model_show
    self.class::MODEL.of_tenant_id(tenant_id)
  end

  def record_show
    user = super
    user.tenant_context = tenant_id
    user
  end

  def record_update
    user = super
    user.tenant_context = tenant_id
    user
  end

  # return the tenant_id from filter[tenant_id] if the current_user is member of that tenant
  def tenant_id
    (current_user.tenants.pluck(:id) & [params_json_api[:tenant_id]]).first || raise("MISSING_TENANT_ID")
  end

  def json_api_permits
    super + [:tenant_id]
  end

  def cando
    CANDO.merge({
      index: %w(
        ~/list-tenant-users.reader
      ),
      show: %w(
        ~/list-tenant-users.reader
      ),
      update: %W(
        ~/list-tenant-users.writer
      )
    })
  end

end
