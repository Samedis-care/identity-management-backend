require 'rails_helper'
require Rails.root.join('db/migrate_manual/20260803081500_repair_missing_standard_user_mappings')

# Cover for the manual repair migration for Samedis-care/samedis-care-issues#2403.
# Runs scoped to its own tenant via TENANT_ID so leftovers from other specs cannot
# influence the outcome.
RSpec.describe RepairMissingStandardUserMappings do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "repair-#{sfx}@invite-spec.test" }

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
      first_name: 'Repair',
      last_name: 'Spec',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  # the state the bug left behind: accepted, done, but no mapping
  let!(:invite) do
    Invite.create!(
      email: email,
      tenant: tenant,
      invitable_type: 'tenant',
      invitable_id: tenant.id.to_s,
      auto_accept: true,
      valid_until: 1.day.from_now
    ).tap { |i| i.set(done: true, accepted_at: Time.utc(2025, 6, 1)) }
  end

  around do |example|
    was_verbose = Mongoid::Migration.verbose
    Mongoid::Migration.verbose = false
    ENV['TENANT_ID'] = tenant.id.to_s
    example.run
  ensure
    Mongoid::Migration.verbose = was_verbose
    ENV.delete('TENANT_ID')
    ENV.delete('APPLY')
    ENV.delete('LIMIT')
    ENV.delete('SINCE')
  end

  after do
    Invite.where(email: email).delete_all
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    user_actor&.delete
    user.delete
    tenant.delete
  end

  def mappings
    Actors::Mapping.where(parent: standard_group, map_actor: user_actor)
  end

  describe 'without APPLY' do
    it 'writes nothing' do
      expect { described_class.up rescue nil }.not_to change { mappings.count }.from(0)
    end

    it 'raises so the migration is not recorded as run' do
      expect { described_class.up }.to raise_error(/DRY RUN/)
    end
  end

  describe 'with APPLY' do
    before { ENV['APPLY'] = 'true' }

    it 'maps the user into standard_user' do
      expect { described_class.up }.to change { mappings.count }.from(0).to(1)
    end

    it 'is idempotent' do
      described_class.up
      described_class.up

      expect(mappings.count).to eq(1)
    end

    it 'leaves an already mapped user untouched' do
      standard_group.map_into!(user_actor)

      expect { described_class.up }.not_to change { mappings.count }.from(1)
    end

    it 'respects LIMIT' do
      ENV['LIMIT'] = '0'

      expect { described_class.up }.not_to change { mappings.count }.from(0)
    end

    # a user who reaches the tenant through another group is not this bug, and their
    # missing standard_user mapping may well be deliberate
    it 'skips users who already have other access to the tenant' do
      other_group = Actors::Group.create!(
        name: "custom_#{sfx}", parent: tenant_profiles, system: true
      )
      other_group.map_into!(user_actor)

      expect { described_class.up }.not_to change { mappings.count }.from(0)
    end

    it 'ignores invites that were never accepted' do
      invite.set(done: false, accepted_at: nil)

      expect { described_class.up }.not_to change { mappings.count }.from(0)
    end

    # 68 of the first live report's 94 affected rows predate the bug, going back to 2019,
    # so the default floor keeps the repair to rows this bug can actually explain
    context 'with an acceptance date before the bug' do
      before { invite.set(accepted_at: Time.utc(2024, 10, 1)) }

      it 'does not repair by default' do
        expect { described_class.up }.not_to change { mappings.count }.from(0)
      end

      it 'still counts it as affected in the report' do
        expect(described_class).to receive(:report) do |stats, _months, _apply, since|
          expect(stats[:affected]).to eq(1)
          expect(stats[:skip_before_since]).to eq(1)
          expect(stats[:in_repair_scope]).to eq(0)
          expect(since).to eq(described_class::BUG_INTRODUCED)
        end

        described_class.up
      end

      it 'repairs with SINCE=all' do
        ENV['SINCE'] = 'all'

        expect { described_class.up }.to change { mappings.count }.from(0).to(1)
      end

      it 'repairs with an explicit earlier SINCE' do
        ENV['SINCE'] = '2024-01-01'

        expect { described_class.up }.to change { mappings.count }.from(0).to(1)
      end
    end

    it 'does not repair invites with no acceptance date' do
      invite.set(accepted_at: nil)

      expect { described_class.up }.not_to change { mappings.count }.from(0)
    end
  end

  describe 'SINCE parsing' do
    it 'rejects input Time.parse would silently misread' do
      ENV['SINCE'] = '2025'

      expect { described_class.since_floor }.to raise_error(/SINCE must be YYYY-MM-DD/)
    end

    it 'rejects nonsense instead of aborting with a bare ArgumentError' do
      ENV['SINCE'] = 'letztes jahr'

      expect { described_class.since_floor }.to raise_error(/SINCE must be YYYY-MM-DD/)
    end

    it 'accepts a full date' do
      ENV['SINCE'] = '2024-01-01'

      expect(described_class.since_floor).to eq(Time.utc(2024, 1, 1))
    end
  end

  describe 'LIMIT and the printed audit list' do
    before do
      ENV['APPLY'] = 'true'
      ENV['LIMIT'] = '0'
    end

    it 'does not list rows it did not repair' do
      expect(described_class).to receive(:report) do |stats, _months, _apply, _since, in_scope|
        expect(stats[:in_repair_scope]).to eq(1)
        expect(stats[:over_limit]).to eq(1)
        expect(in_scope).to be_empty
      end

      described_class.up
    end
  end

  describe '.down' do
    it 'refuses to reverse' do
      expect { described_class.down }.to raise_error(Mongoid::IrreversibleMigration)
    end
  end
end
