require 'rails_helper'

# Regression guard for the cross-tenant enumeration fix (pen-test Issue 1).
#
# GET /api/v1/user/tenant (and show/update/destroy, which resolve through
# #model_index) must return only the caller's own tenants unless the caller
# actually holds the app-wide `app-tenant.admin` cando in one of their tenants.
# The previous guard relied on cando_any_for_tenants? in a boolean context
# while it returned an Array (always truthy), so every user got every tenant.
#
# This drives the real predicate (JsonApiController#cando_any_for_tenants? ->
# #tenants_with_cando -> #cando_any?) against stubbed tenant memberships.
RSpec.describe Api::V1::User::TenantsController do
  subject(:controller_instance) { described_class.new }

  let(:own_tenant_ids) { [BSON::ObjectId.new, BSON::ObjectId.new] }
  let(:actor) { double('Actors::User', actor_ids: own_tenant_ids) }
  let(:user)  { double('User', actor: actor) }

  # The test env has no Devise secret configured, so the first lazy route load
  # (devise_for :users) would raise. Set one so the controller can be exercised.
  before { Devise.secret_key ||= 'test-suite-secret' }

  # tenant_candos_per_membership: one candos-array per tenant the user belongs to.
  # Mongoid criteria are built in memory (no DB); a tenant-scoped result carries
  # an `_id` selector (from where(:id.in => actor_ids)), the all-tenants result
  # does not.
  def index_selector(tenant_candos_per_membership)
    tenants = tenant_candos_per_membership.map { |candos| { candos: candos } }
    allow(user).to receive(:tenants).and_return(tenants)
    without_partial_double_verification do
      allow(controller_instance).to receive(:current_user).and_return(user)
      allow(controller_instance).to receive(:current_app).and_return('samedis-care')
    end
    controller_instance.send(:model_index).selector
  end

  it 'scopes a user with no tenants to their own memberships' do
    expect(index_selector([])).to have_key('_id')
  end

  it 'scopes a user holding only a per-tenant cando (tenant.admin) to their own tenants' do
    expect(index_selector([['samedis-care/tenant.admin']])).to have_key('_id')
  end

  it 'does not scope by tenant id for an app-tenant.admin (sees all tenants)' do
    expect(index_selector([['samedis-care/app-tenant.admin']])).not_to have_key('_id')
  end

  it 'restricts the own-tenant scope to exactly the caller actor_ids' do
    expect(index_selector([['samedis-care/tenant.admin']])['_id']).to eq('$in' => own_tenant_ids)
  end
end
