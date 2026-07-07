require 'rails_helper'

# Regression guard for the cross-tenant authorization fix (security audit C-1).
#
# Api::V1::Apps::Tenants::UsersController scopes its data by a tenant taken from
# the request path (params[:tenant_id]) and allows updating users (incl.
# set_password). It MUST authorize per-tenant via `tenant_authorize` (which
# checks the required cando against current_tenant — the tenant the current_user
# is actually a MEMBER of). It must NOT use the default `authorize`, which
# evaluates the cando against User#global_candos (the union across ALL tenants)
# and therefore lets a tenant.admin of one tenant act on every other tenant.
RSpec.describe Api::V1::Apps::Tenants::UsersController, type: :model do
  def before_filters(controller)
    controller._process_action_callbacks
              .select { |c| c.kind == :before }
              .map(&:filter)
  end

  it 'authorizes per-tenant via :tenant_authorize' do
    expect(before_filters(described_class)).to include(:tenant_authorize)
  end

  it 'does not fall back to the global :authorize' do
    expect(before_filters(described_class)).not_to include(:authorize)
  end
end
