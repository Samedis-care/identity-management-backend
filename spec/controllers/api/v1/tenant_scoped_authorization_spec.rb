require 'rails_helper'

# Regression guard for the cross-tenant authorization fix (security audit C-1/H-6/M-9).
#
# These controllers scope their data by a tenant taken from the request path
# (params[:tenant_id]). They MUST authorize per-tenant via `tenant_authorize`
# (which checks the required cando against current_tenant — the tenant the
# current_user is actually a MEMBER of). They must NOT use the default
# `authorize`, which evaluates the cando against User#global_candos — the union
# of a user's candos across ALL tenants — and therefore lets a tenant.admin of
# one tenant act on every other tenant.
RSpec.describe 'tenant-scoped controller authorization', type: :model do
  TENANT_SCOPED_CONTROLLERS = [
    Api::V1::Apps::Tenants::UsersController,
    Api::V1::AccessControl::Tenant::ProfilesController,
    Api::V1::AccessControl::Tenant::RolesController
  ].freeze

  def before_filters(controller)
    controller._process_action_callbacks
              .select { |c| c.kind == :before }
              .map(&:filter)
  end

  TENANT_SCOPED_CONTROLLERS.each do |controller|
    describe controller.name do
      it 'authorizes per-tenant via :tenant_authorize' do
        expect(before_filters(controller)).to include(:tenant_authorize)
      end

      it 'does not fall back to the global :authorize' do
        expect(before_filters(controller)).not_to include(:authorize)
      end
    end
  end
end
