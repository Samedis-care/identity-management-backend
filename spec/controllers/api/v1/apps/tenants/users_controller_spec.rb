require 'rails_helper'

# App > Tenants > (tenant) > Users (Samedis-care/samedis-care-issues#3530).
#
# App-wide admin candos must pass for a tenant the caller is not a member of,
# while ~/tenant.admin must only count IN the path tenant (security audit C-1).
#
# This drives the real predicate (#tenant_authorization -> JsonApiController /
# User#cando_any?) against stubbed tenant memberships.
RSpec.describe Api::V1::Apps::Tenants::UsersController do
  subject(:controller_instance) { described_class.new }

  let(:path_tenant_id)  { BSON::ObjectId.new.to_s }
  let(:other_tenant_id) { BSON::ObjectId.new.to_s }
  let(:app_actor) { double('Actors::App', name: 'samedis-care') }
  let(:user) { User.new }

  # memberships: { tenant_id => [candos held in that tenant] }
  def authorized?(action, memberships)
    allow(user).to receive_messages(
      tenants: memberships.map { |id, candos| { id: id, candos: candos } },
      candos: memberships
    )
    without_partial_double_verification do
      allow(controller_instance).to receive_messages(
        current_user: user,
        current_app_actor: app_actor,
        params: ActionController::Parameters.new(action: action, tenant_id: path_tenant_id),
        params_json_api: ActionController::Parameters.new({})
      )
    end
    controller_instance.send(:tenant_authorization)
  end

  describe 'a caller who is not a member of the path tenant' do
    %w(index show).each do |action|
      it "allows an app-tenant.admin to #{action}" do
        expect(authorized?(action, other_tenant_id => ['samedis-care/app-tenant.admin'])).to be(true)
      end
    end

    # app-wide it would reach set_password of every user in the app
    it 'refuses an app-tenant.admin an update' do
      expect(authorized?('update', other_tenant_id => ['samedis-care/app-tenant.admin'])).to be(false)
    end

    it 'allows apps.admin + users.reader to list, as App > Users does' do
      candos = ['samedis-care/apps.admin', 'identity-management/users.reader']
      expect(authorized?('index', other_tenant_id => candos)).to be(true)
    end

    it 'refuses apps.admin + users.reader an update' do
      candos = ['samedis-care/apps.admin', 'identity-management/users.reader']
      expect(authorized?('update', other_tenant_id => candos)).to be(false)
    end

    it 'allows apps.admin + users.writer an update' do
      candos = ['samedis-care/apps.admin', 'identity-management/users.writer']
      expect(authorized?('update', other_tenant_id => candos)).to be(true)
    end

    it 'refuses apps.admin without users.reader' do
      expect(authorized?('index', other_tenant_id => ['samedis-care/apps.admin'])).to be(false)
    end

    it 'refuses an app-wide cando of another app' do
      expect(authorized?('index', other_tenant_id => ['other-app/app-tenant.admin'])).to be(false)
    end

    %w(index show update).each do |action|
      it "refuses a tenant.admin of another tenant to #{action} (C-1)" do
        expect(authorized?(action, other_tenant_id => ['samedis-care/tenant.admin'])).to be(false)
      end
    end
  end

  describe 'a member of the path tenant' do
    it 'allows a tenant.admin of that tenant' do
      expect(authorized?('update', path_tenant_id => ['samedis-care/tenant.admin'])).to be(true)
    end

    it 'allows an app-tenant.admin of that tenant an update' do
      expect(authorized?('update', path_tenant_id => ['samedis-care/app-tenant.admin'])).to be(true)
    end

    it 'refuses a member without an admin cando' do
      expect(authorized?('index', path_tenant_id => ['samedis-care/users.reader'])).to be(false)
    end
  end
end
