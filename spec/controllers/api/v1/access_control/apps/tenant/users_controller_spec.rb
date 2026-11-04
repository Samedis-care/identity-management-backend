require 'rails_helper'

# App > Tenants > (tenant) > Users, remove/edit access
# (Samedis-care/samedis-care-issues#3623).
#
# The IM admin candos must pass for a tenant the caller is not a member of,
# while ~/access-control.* must only count IN the path tenant (security audit C-1).
#
# This drives the real predicate (#tenant_authorization -> JsonApiController /
# User#cando_any?) against stubbed tenant memberships.
RSpec.describe Api::V1::AccessControl::Apps::Tenant::UsersController do
  subject(:controller_instance) { described_class.new }

  let(:path_tenant_id)  { BSON::ObjectId.new.to_s }
  let(:other_tenant_id) { BSON::ObjectId.new.to_s }
  let(:app_actor) { double('Actors::App', name: 'samedis-care') }
  let(:path_tenant_actor) { double('Actors::Tenant', id: BSON::ObjectId.from_string(path_tenant_id)) }
  let(:user) { User.new }

  # memberships: { tenant_id => [candos held in that tenant] }
  def stub_request(action, memberships)
    allow(user).to receive_messages(
      tenants: memberships.map { |id, candos| { id: id, candos: candos } },
      candos: memberships
    )
    params = ActionController::Parameters.new(action: action, tenant_id: path_tenant_id)
    without_partial_double_verification do
      allow(controller_instance).to receive_messages(
        current_user: user,
        current_app_actor: app_actor,
        current_tenant_actor: path_tenant_actor,
        params: params,
        params_json_api: params
      )
    end
  end

  def authorized?(action, memberships)
    stub_request(action, memberships)
    controller_instance.send(:tenant_authorization)
  end

  def resolved_tenant_id(action, memberships)
    stub_request(action, memberships)
    controller_instance.send(:tenant_id)
  end

  describe 'a caller who is not a member of the path tenant' do
    %w(index show update destroy).each do |action|
      it "allows an IM apps.admin to #{action}" do
        expect(authorized?(action, other_tenant_id => ['identity-management/apps.admin'])).to be(true)
      end
    end

    it 'allows an IM global.admin to remove access' do
      expect(authorized?('destroy', other_tenant_id => ['identity-management/global.admin'])).to be(true)
    end

    it 'resolves the path tenant for an IM admin' do
      expect(resolved_tenant_id('destroy', other_tenant_id => ['identity-management/apps.admin']))
        .to eq(path_tenant_id)
    end

    %w(index destroy).each do |action|
      it "refuses access-control.writer of another tenant to #{action} (C-1)" do
        candos = ['samedis-care/access-control.reader', 'samedis-care/access-control.writer']
        expect(authorized?(action, other_tenant_id => candos)).to be(false)
      end
    end

    it 'does not resolve the path tenant without an IM admin cando' do
      expect { resolved_tenant_id('destroy', other_tenant_id => ['samedis-care/access-control.writer']) }
        .to raise_error(RuntimeError, 'MISSING_TENANT_ID')
    end
  end

  describe 'a member of the path tenant' do
    it 'allows access-control.writer of that tenant to remove access' do
      expect(authorized?('destroy', path_tenant_id => ['samedis-care/access-control.writer'])).to be(true)
    end

    it 'resolves the path tenant from the membership' do
      expect(resolved_tenant_id('destroy', path_tenant_id => ['samedis-care/access-control.writer']))
        .to eq(path_tenant_id)
    end

    it 'refuses a member without an access-control or IM admin cando' do
      expect(authorized?('destroy', path_tenant_id => ['samedis-care/tenant.admin'])).to be(false)
    end
  end
end
