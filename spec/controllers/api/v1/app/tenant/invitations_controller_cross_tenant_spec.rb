require 'rails_helper'

# Repro for Samedis-care/samedis-care-issues#3408.
#
# POST /api/v1/:app/:tenant_id/invitations is authorized by JsonApiController#authorization,
# which checks the cando against User#global_candos - the union over ALL of the caller's
# tenants - instead of the tenant in the path (#tenant_authorize). record_create then stamps
# the invite with the path tenant. So a user who may write invitations in tenant A, and is a
# plain member of tenant B, can invite themself into one of B's access groups and accept it.
#
# Authentication is stubbed at its boundary (authenticate_user!, current_token,
# current_app_actor); the authorization chain, the invite and its acceptance are real.
RSpec.describe Api::V1::App::Tenant::InvitationsController, type: :controller do
  let(:app_name) { 'samedis-care' }
  let(:writer_cando) { "#{app_name}/invitations.writer" }
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "cross-tenant-#{sfx}@invite-spec.test" }

  let!(:tenant_a) { Actors::Tenant.create!(name: "a#{sfx}") }
  let!(:tenant_b) { Actors::Tenant.create!(name: "b#{sfx}") }
  let!(:org_b) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant_b) }
  let!(:b_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: org_b) }
  # system: true skips Group#safe_role_ids, which needs app actor defaults this spec has not seeded
  let!(:b_admin_group) { Actors::Group.create!(name: 'tenant_admins', parent: b_profiles, system: true) }

  let!(:user) do
    User.new(
      email: email,
      email_confirmation: email,
      first_name: 'Cross',
      last_name: 'Tenant',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  # The test env has no Devise secret configured; the first lazy route load needs one.
  before { Devise.secret_key ||= 'test-suite-secret' }

  after do
    Invite.where(email: email).delete_all
    Actors::Mapping.where(map_actor_id: user_actor&.id).delete_all
    Actor.where(:parent_ids.in => [tenant_a.id, tenant_b.id]).delete_all
    user_actor&.delete
    user.delete
    tenant_a.delete
    tenant_b.delete
  end

  # candos_by_tenant: { tenant => [cando, ...] } - the caller's memberships
  def sign_in_with(candos_by_tenant)
    tenants = candos_by_tenant.map { |tenant, candos| { id: tenant.id, candos: candos } }
    allow(user).to receive_messages(tenants: tenants,
                                    candos: candos_by_tenant.to_h { |t, c| [t.id.to_s, c] })
    without_partial_double_verification do
      allow(controller).to receive_messages(authenticate_user!: nil,
                                            current_user: user,
                                            current_token: double(otp_satisfied?: true),
                                            current_app: app_name,
                                            current_app_actor: double(name: app_name))
    end
  end

  def invite_self_into_b_admins
    post :create, params: {
      app: app_name,
      tenant_id: tenant_b.id.to_s,
      data: {
        email: email,
        invitable_type: 'access_control',
        actions: { add_access_group_ids: [b_admin_group.id.to_s] }
      }
    }
  end

  def invites_into_b
    Invite.where(email: email, tenant_id: tenant_b.id.to_s)
  end

  def b_admin_mappings
    Actors::Mapping.where(parent: b_admin_group, map_actor: user_actor)
  end

  context 'when the caller may write invitations in tenant A only and is a plain member of B' do
    before do
      sign_in_with(tenant_a => [writer_cando], tenant_b => [])
      invite_self_into_b_admins
    end

    it 'refuses the invitation for tenant B' do
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates no invitation for tenant B' do
      expect(invites_into_b.count).to eq(0)
    end

    it 'does not get the caller into B\'s admin group by accepting' do
      invites_into_b.each(&:accept!)

      expect(b_admin_mappings.count).to eq(0)
    end
  end

  context 'when the caller may write invitations in tenant B' do
    before do
      sign_in_with(tenant_b => [writer_cando])
      invite_self_into_b_admins
    end

    it 'creates the invitation for tenant B' do
      expect(response).to have_http_status(:ok)
      expect(invites_into_b.count).to eq(1)
    end
  end
end
