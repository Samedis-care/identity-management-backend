require 'rails_helper'

# Regression cover for the inverted guard in Invite#_process_accept_tenant that made
# the Samedis.care "auto join facility" feature (Staff#login_allowed) a silent no-op.
# See Samedis-care/samedis-care-issues#2403
RSpec.describe Invite, type: :model do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "invite-#{sfx}@invite-spec.test" }

  let!(:tenant) { Actors::Tenant.create!(name: "t#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }

  let!(:user) do
    User.new(
      email: email,
      email_confirmation: email,
      first_name: 'Invite',
      last_name: 'Spec',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      # the confirmation mail needs an app context we do not have here
      u.skip_confirmation!
      u.save!
    end
  end

  # held separately so cleanup still works in examples that detach the actor
  let!(:user_actor) { user.actor }

  # delete instead of destroy: skips the actor callbacks (cache expiry, write protection)
  # which are irrelevant here and would only slow the suite down
  after do
    Invite.where(email: email).delete_all
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    user_actor&.delete
    user.delete
    tenant.delete
  end

  describe "#accept! with invitable_type 'tenant'" do
    subject(:invite) do
      Invite.create!(
        email: email,
        tenant: tenant,
        invitable_type: 'tenant',
        invitable_id: tenant.id.to_s,
        auto_accept: true,
        valid_until: 1.day.from_now
      )
    end

    def mappings_into(group)
      Actors::Mapping.where(parent: group, map_actor: user.actor)
    end

    context 'when the tenant has the system group standard_user' do
      let!(:standard_group) do
        Actors::Group.create!(name: 'standard_user', parent: tenant_profiles, system: true)
      end

      it 'maps the user into standard_user' do
        expect { invite.accept! }.to change { mappings_into(standard_group).count }.from(0).to(1)
      end

      it 'marks the invite as accepted' do
        invite.accept!

        expect(invite.reload.done).to be(true)
        expect(invite.accepted_at).to be_present
      end

      it 'does not map the user twice when accepted again' do
        invite.accept!
        invite.accept!

        expect(mappings_into(standard_group).count).to eq(1)
      end

      it 'reports and stays retryable when the user has no actor to map' do
        allow(Sentry).to receive(:capture_exception)
        user.set(actor_id: nil)

        expect { invite.accept! }.not_to raise_error
        expect(invite.reload.done).to be(false)
        expect(Sentry).to have_received(:capture_exception)
      end
    end

    # soft-deleting an ancestor cascades through Actor#before_save with a raw
    # `descendants.set(deleted: ...)`, which skips both the system protection guard and
    # the rename applied to the deleted record itself - so the group keeps its name and
    # system flag and would otherwise still be found here
    context 'when the standard_user group sits in a soft-deleted subtree' do
      let!(:deleted_group) do
        Actors::Group.create!(name: 'standard_user', parent: tenant_profiles, system: true)
                     .tap { |g| g.set(deleted: true) }
      end

      it 'does not map into it and leaves the invite retryable' do
        allow(Sentry).to receive(:capture_message)

        expect(invite.accept!).to be(false)
        expect(mappings_into(deleted_group).count).to eq(0)
        expect(invite.reload.done).to be(false)
      end

      it 'still maps into a live group next to the deleted one' do
        live_group = Actors::Group.create!(
          name: 'standard_user_live', parent: tenant_profiles, system: true
        )
        live_group.set(name: 'standard_user')

        expect { invite.accept! }.to change { mappings_into(live_group).count }.from(0).to(1)
      end
    end

    context 'when the tenant has no standard_user group' do
      it 'does not accept the invite, so the next login retries it' do
        allow(Sentry).to receive(:capture_message)

        expect(invite.accept!).to be(false)
        expect(invite.reload.done).to be(false)
        expect(invite.accepted_at).to be_nil
      end

      it 'reports the misconfigured tenant' do
        expect(Sentry).to receive(:capture_message).with(/standard_user/, hash_including(level: :error))

        invite.accept!
      end

      it 'does not raise, so the login flow stays usable' do
        allow(Sentry).to receive(:capture_message)

        expect { invite.accept! }.not_to raise_error
      end
    end

    # the `system: true` filter is deliberate - a customer-created group of the same
    # name must not be able to hand out the samedis-care-employee role
    context 'when standard_user exists but is not a system group' do
      # created as a system group and then flipped via #set: Actors::Group#safe_role_ids
      # validates non-system groups against the tenant's actor defaults, which are not
      # seeded in the test database
      let!(:custom_group) do
        Actors::Group.create!(name: 'standard_user', parent: tenant_profiles, system: true)
                     .tap { |g| g.set(system: false) }
      end

      it 'ignores it and leaves the invite retryable' do
        allow(Sentry).to receive(:capture_message)

        expect(invite.accept!).to be(false)
        expect(mappings_into(custom_group).count).to eq(0)
        expect(invite.reload.done).to be(false)
      end
    end
  end

  # #accept! only marks an invite done when the processor reports success, so cover
  # that the other processor still burns its invite
  describe "#accept! with invitable_type 'access_control'" do
    subject(:invite) do
      Invite.create!(
        email: email,
        tenant: tenant,
        invitable_type: 'access_control',
        invitable_id: tenant.id.to_s,
        actions: {},
        auto_accept: true,
        valid_until: 1.day.from_now
      )
    end

    it 'marks the invite as accepted' do
      invite.accept!

      expect(invite.reload.done).to be(true)
    end
  end
end
