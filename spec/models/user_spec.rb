require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2810: User#recent_invites used to
# be scoped by created_at only, so an invite accepted more than 24h after it was created
# never surfaced again in AppUserSerializer#recent_invite_tokens - even though
# #auto_accept_invites! (called earlier in the same login request, see
# Api::V1::App::Doorkeeper::TokensController#create) had just accepted it. That silently
# broke consuming apps (e.g. samedis-care-backend's accept_recent_invites) which rely on
# recent_invite_tokens to know which invites just became actionable.
RSpec.describe User, type: :model do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "recent-invites-#{sfx}@invite-spec.test" }

  let!(:tenant) { Actors::Tenant.create!(name: "t#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:standard_group) do
    Actors::Group.create!(name: 'standard_user', parent: tenant_profiles, system: true)
  end

  let!(:user) do
    User.new(
      email: email,
      email_confirmation: email,
      first_name: 'Recent',
      last_name: 'Invites',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      # the confirmation mail needs an app context we do not have here
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  after do
    Invite.where(email: email).delete_all
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    user_actor&.delete
    user.delete
    tenant.delete
  end

  def make_invite
    Invite.create!(
      email: email,
      user: user,
      tenant: tenant,
      invitable_type: 'tenant',
      invitable_id: tenant.id.to_s,
      auto_accept: true,
      valid_until: 1.year.from_now
    )
  end

  describe '#recent_invites' do
    it 'includes an invite created long ago but accepted within the last day' do
      invite = make_invite
      # backdate via #set (bypasses callbacks, so it actually sticks) to simulate an
      # invite that was created well outside the 1-day window
      invite.set(created_at: 5.days.ago, updated_at: 5.days.ago)

      expect(invite.accept!).to be(true) # standard_user group present, so this succeeds and saves
      expect(invite.reload.done).to be(true)

      expect(user.reload.recent_invites.pluck(:id)).to include(invite.id)
    end

    it 'excludes an invite that was neither created nor accepted within the last day' do
      invite = make_invite
      invite.set(created_at: 5.days.ago, updated_at: 5.days.ago)

      expect(user.reload.recent_invites.pluck(:id)).not_to include(invite.id)
    end

    it 'includes a freshly created, not-yet-accepted invite' do
      invite = make_invite

      expect(user.reload.recent_invites.pluck(:id)).to include(invite.id)
    end
  end
end
