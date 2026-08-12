require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2394: an admin
# removing a user's access to a tenant (Api::V1::AccessControl::Tenant::
# UsersController#destroy sets access_group_ids = []) reported success
# while the user's access never actually cleared, because the group
# backing their membership had been deleted/merged elsewhere without
# cleaning up the Actors::Mapping join record.
RSpec.describe User, '#set_access_group_ids=' do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "orphan-groups-#{sfx}@access-group-spec.test" }

  let!(:tenant) { Actors::Tenant.create!(name: "t#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:group) { Actors::Group.create!(name: "group#{sfx}", parent: tenant_profiles, system: true) }

  let!(:user) do
    described_class.new(
      email: email,
      email_confirmation: email,
      first_name: 'Orphan',
      last_name: 'Groups',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  after do
    Actors::Mapping.where(map_actor: user_actor).delete_all
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    user_actor&.delete
    user.delete
    tenant.delete
  end

  def mappings
    Actors::Mapping.where(map_actor: user_actor)
  end

  context 'when a mapped group no longer exists (orphaned mapping)' do
    before do
      group.map_into!(user_actor)
      # the state the underlying bug leaves behind: the mapping survives
      # a group deletion/merge that should have cascaded
      group.delete
    end

    it 'removes the dangling mapping when access is fully cleared' do
      user.tenant_context = tenant.id

      expect do 
        user.access_group_ids = []
        user.save!(validate: false)
      end
        .to change(mappings, :count).from(1).to(0)
    end

    it 'no longer reports the dead group id afterwards' do
      user.tenant_context = tenant.id
      user.access_group_ids = []
      user.save!(validate: false)

      # fresh object — the in-memory User instance memoizes
      # tenant_access_group_ids across the save, so re-reading the
      # attribute off `user` itself would return a stale value
      fresh = described_class.find(user.id)
      fresh.tenant_context = tenant.id
      expect(fresh.access_group_ids.to_a).to be_empty
    end
  end

  context 'when the group still exists' do
    it 'still maps a selected group normally (not swept up as if orphaned)' do
      user.tenant_context = tenant.id

      expect do 
        user.access_group_ids = [group.id.to_s]
        user.save!(validate: false)
      end
        .to change(mappings, :count).from(0).to(1)

      fresh = described_class.find(user.id)
      fresh.tenant_context = tenant.id
      expect(fresh.access_group_ids.to_a).to eq([group.id.to_s])
    end
  end
end
