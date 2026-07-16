require 'rails_helper'

# Regression guard for the cross-tenant enumeration fix (pen-test Issue 1).
#
# GET /api/v1/user/tenant (and show/update/destroy, which resolve through
# #model_index) must return only the caller's own tenants unless the caller
# actually holds the app-wide `app-tenant.admin` cando. The previous guard
# `if cando_any_for_tenants?("...app-tenant.admin")` was always truthy
# (an Array is truthy; the cando was passed as a String), so every user got
# every tenant on the platform.
RSpec.describe Api::V1::User::TenantsController do
  subject(:controller_instance) { described_class.new }

  let(:own_tenant_ids) { [BSON::ObjectId.new, BSON::ObjectId.new] }
  let(:actor) { double('Actors::User', actor_ids: own_tenant_ids) }
  let(:user)  { double('User', actor: actor) }

  # The test env has no Devise secret configured, so the first lazy route load
  # (devise_for :users) would raise. Set one so the controller can be exercised.
  before { Devise.secret_key ||= 'test-suite-secret' }

  # Mongoid criteria are built in memory (no DB). A tenant-scoped result carries
  # an `_id` selector (from `where(:id.in => actor_ids)`); the all-tenants result
  # does not.
  def index_selector(global_candos)
    allow(user).to receive(:global_candos).and_return(global_candos)
    without_partial_double_verification do
      allow(controller_instance).to receive(:current_user).and_return(user)
      allow(controller_instance).to receive(:current_app).and_return('samedis-care')
    end
    controller_instance.send(:model_index).selector
  end

  it 'scopes a user without the app-tenant.admin cando to their own tenants' do
    expect(index_selector([])).to have_key('_id')
  end

  it 'scopes a user holding only an unrelated cando to their own tenants' do
    expect(index_selector(['samedis-care/tenant.admin'])).to have_key('_id')
  end

  it 'does not scope by tenant id for an app-tenant.admin (sees all tenants)' do
    expect(index_selector(['samedis-care/app-tenant.admin'])).not_to have_key('_id')
  end

  it 'restricts the own-tenant scope to exactly the caller actor_ids' do
    expect(index_selector([])['_id']).to eq('$in' => own_tenant_ids)
  end
end
