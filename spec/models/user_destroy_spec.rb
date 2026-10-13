require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/2849
#
# User#actor and Actor#user both declared `dependent: :destroy`, so User#destroy
# bounced between the two documents until SystemStackError. The cascade now lives
# on User#actor only.
RSpec.describe User do
  subject(:user) do
    _user = described_class.new(
      email: "user-destroy-spec-#{SecureRandom.hex(4)}@test.local",
      first_name: 'Spec',
      last_name: 'Probe',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    )
    _user.email_confirmation = _user.email
    _user.skip_confirmation!
    _user.save!
    _user
  end

  let(:sfx) { SecureRandom.hex(4) }
  let!(:tenant) { Actors::Tenant.create!(name: "t#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:group) { Actors::Group.create!(name: "group-#{sfx}", parent: tenant_profiles, system: true) }
  let!(:actor_id) { user.actor_id }

  after do
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    Actor.where(map_actor_id: actor_id).delete_all
    Actor.where(id: actor_id).delete_all
    user.delete
    tenant.delete
  end

  def memberships
    Actors::Mapping.where(map_actor_id: actor_id)
  end

  describe '#destroy' do
    it 'does not recurse between User and Actors::User' do
      expect { user.destroy }.not_to raise_error
    end

    it 'removes the user document' do
      user.destroy
      expect(described_class.where(id: user.id)).to be_none
    end

    it 'removes the linked Actors::User document' do
      user.destroy
      expect(Actor.where(id: actor_id)).to be_none
    end

    context 'when the user is a member of a group' do
      before { group.map_into!(user.actor) }

      it 'removes the membership mappings that point at the user actor' do
        expect { user.destroy }.to change { memberships.count }.from(1).to(0)
      end

      # system_override is needed: the group is system: true, and Actor#before_destroy
      # aborts such a destroy before destroy_mappings runs, which would make this
      # example pass with or without the fix.
      it 'lets the group be destroyed afterwards instead of raising from the stale mapping' do
        user.destroy
        doomed = group.reload.tap { |g| g.system_override = true }

        expect(doomed.destroy).to be(true)
      end
    end
  end

  # Actors::Mapping used to inherit Actor's `has_one :user, dependent: :destroy`, which
  # resolves through Mapping's own belongs_to :user to the real account, so destroying
  # a membership raised the same SystemStackError (and would have taken the account
  # with it). Actor#destroy_mappings / #destroy_children call it on every group destroy.
  describe 'destroying a membership mapping' do
    before { group.map_into!(user.actor) }

    it 'does not raise' do
      expect { memberships.first.destroy }.not_to raise_error
    end

    it 'leaves the user intact' do
      memberships.first.destroy
      expect(described_class.where(id: user.id)).to exist
    end
  end
end
