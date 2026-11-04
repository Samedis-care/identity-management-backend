class Api::V1::AccessControl::Apps::Tenant::UsersController < Api::V1::JsonApiController

  skip_before_action :authorize
  before_action :tenant_authorize

  # The IM admin candos are held in IM's own tenants, never in the path tenant,
  # so membership-scoped they refused every IM admin (App > Tenants > (tenant) >
  # Users, remove; Samedis-care/samedis-care-issues#3623).
  # ~/access-control.* stays membership-scoped.
  APP_WIDE_CANDOS = {
    index:   %w(identity-management/apps.admin identity-management/global.admin),
    show:    %w(identity-management/apps.admin identity-management/global.admin),
    update:  %w(identity-management/apps.admin identity-management/global.admin),
    destroy: %w(identity-management/apps.admin identity-management/global.admin)
  }.freeze

  PAGE_LIMIT = 20
  PAGE_LIMIT_MAX = 50

  MODEL_BASE = User
  MODEL = User.available
  MODEL_OVERVIEW = User.available
  SERIALIZER = TenantUserAccessSerializer
  OVERVIEW_SERIALIZER = TenantUserAccessOverviewSerializer

  SWAGGER = {
    tag: 'Access Control',
    name: 'Tenant User',
    header: 'Manage user access within a tenant context',
    action_suffix: 'authorized groups'
  }

  PERMIT_UPDATE = [{ access_group_ids: [] }].freeze

  undef_method :create

  def index
    super do |records,opts|
      records = records.collect do |user|
        user.tenant_context = tenant_id
        user
      end
      opts[:meta] ||= {}
      # opts[:meta][:access_groups] = ::AccessControl.for_tenant(tenant_id)
      [records,opts]
    end
  end

  def show
    super do |records,opts|
      opts[:meta] ||= {}
      # opts[:meta][:access_groups] = ::AccessControl.for_tenant(tenant_id)
      [records,opts]
    end
  end

  def update
    super do |records,opts|
      opts[:meta] ||= {}
      # opts[:meta][:access_groups] = ::AccessControl.for_tenant(tenant_id)
      [records,opts]
    end
  end

  def destroy
    raise if params_json_api[:id].eql?(current_user.id)
    # special case, user won't be deleted but this removes current access
    # for this tenant
    record = record_update
    record.access_group_ids = []
    record.save(validate: false)
    check_for_errors(record) || return
    render_serialized_record(record: record)
  end

  private

  def model_index
    self.class::MODEL_OVERVIEW.of_tenant_id(tenant_id).set_field_map({ access_group_ids: "tenant_access_group_ids.#{tenant_id}" })
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
    record_show
  end

  # return the tenant_id from filter[tenant_id] if the current_user is member of that tenant,
  # or, for an app-wide admin, if the tenant belongs to the app in the path
  def tenant_id
    @tenant_id ||= (current_user.tenants.pluck(:id) & [params_json_api[:tenant_id]]).first ||
                   (current_tenant_actor.id.to_s if app_wide_authorization) ||
                   raise('MISSING_TENANT_ID')
  end

  def json_api_permits
    super + [:tenant_id]
  end

  def cando
    CANDO.merge({
      index:   %w(~/access-control.reader identity-management/apps.admin identity-management/global.admin),
      show:    %w(~/access-control.reader identity-management/apps.admin identity-management/global.admin),
      update:  %w(~/access-control.writer identity-management/apps.admin identity-management/global.admin),
      destroy: %w(~/access-control.writer identity-management/apps.admin identity-management/global.admin)
    })
  end

end
