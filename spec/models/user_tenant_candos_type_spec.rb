require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2806: User#get_tenant_candos'
# `rescue []` persisted an Array into the Hash-typed `tenant_candos_cached`, and
# Actor.tenant_collection's `user.candos.dig(t.id.to_s)` then raised
# `TypeError: no implicit conversion of String into Integer` (Array#dig only
# accepts an Integer index) -- a 500 on every request that serialises the user
# until the cache was next invalidated.
RSpec.describe 'tenant_candos_cached type safety' do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "candos-type-#{sfx}@tenant-candos-spec.test" }

  let!(:user) do
    User.new(
      email: email,
      email_confirmation: email,
      first_name: 'Candos',
      last_name: 'Type',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  after do
    # user.delete skips callbacks, so the Actors::User actor (and any
    # mappings) created by User's after_save survive unless cleaned up
    # explicitly -- see spec/models/user_set_access_group_ids_spec.rb.
    Actors::Mapping.where(map_actor: user_actor).delete_all
    user_actor&.delete
    user.delete
  end

  describe 'User#get_tenant_candos / #candos' do
    context 'when the user has no Actors::Mapping at all' do
      it 'returns a Hash, not an Array' do
        expect(user.get_tenant_candos).to eq({})
      end

      it 'persists the Hash via #candos so Actor.tenant_collection can dig it safely' do
        user.candos
        expect(user.reload.tenant_candos_cached).to eq({})
      end
    end

    context 'when the tenant_candos aggregation itself fails' do
      it 'raises instead of caching the failure as an empty result' do
        allow(Actors::Mapping).to receive(:get_tenant_candos).and_raise(Mongo::Error::SocketTimeoutError, 'boom')

        expect { user.candos }.to raise_error(Mongo::Error::SocketTimeoutError)
        # nothing was persisted -- self.set(...) never runs because evaluating
        # its tenant_candos_cached: get_tenant_candos argument raised first
        expect(user.reload.tenant_candos_cached).to be_nil
      end
    end

    context 'when tenant_candos_cached already holds a stray Array with a fresh timestamp (legacy poisoned data)' do
      it 'treats the cache as invalid and heals it, rather than trusting the non-nil timestamp' do
        user.set(tenant_candos_cached: [], tenant_candos_cached_at: Time.now)

        result = user.reload.candos

        expect(result).to be_a(Hash)
        expect(user.reload.tenant_candos_cached).to eq({})
      end
    end

    # Regression cover for Samedis-care/samedis-care-issues#2808:
    # get_tenant_candos used to assign its own return value -- a
    # tenant_id => [cando strings] Hash -- into tenant_access_group_ids, a
    # field that must hold tenant_id => [group actor ids]. That assignment
    # was pure side effect (only the return value is used by #candos), and
    # since the tenant_access_group_ids reader only re-derives when the hash
    # has zero keys, a poisoned value never self-healed.
    context 'when the candos cache is recomputed' do
      let!(:tenant) { Actors::Tenant.create!(name: "candos-808-tenant-#{sfx}") }
      let!(:organization) { Actors::Organization.create!(name: "org-808-#{sfx}", parent: tenant) }
      let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
      let!(:group) { Actors::Group.create!(name: "group-808-#{sfx}", parent: tenant_profiles, system: true) }

      before do
        group.map_into!(user_actor)
        user.tenant_context = tenant.id
        # Simulate a tenant with real cached candos, matching the shape
        # Actors::Mapping.get_tenant_candos returns: an array of hashes
        # keyed by the aggregation's projected field name.
        allow(Actors::Mapping).to receive(:get_tenant_candos).and_return(
          [{ tenant_candos_cached: { tenant.id.to_s => ['samedis-care/devices.reader'] } }]
        )
      end

      after do
        Actor.where(:parent_ids.in => [tenant.id]).delete_all
        tenant.delete
      end

      it 'does not write cando strings into tenant_access_group_ids' do
        user.candos

        # in-memory: the assignment this issue removes would have left this
        # dirty with cando strings under the tenant key
        expect(user.tenant_access_group_ids.values.flatten).not_to include('samedis-care/devices.reader')
      end

      it 'still resolves access_group_ids to the real mapped group id, not cando strings' do
        user.candos

        expect(user.access_group_ids.to_a).to eq([group.id.to_s])
      end

      it 'does not persist cando strings into tenant_access_group_ids on a later save' do
        user.candos
        user.save!(validate: false)

        persisted = user.reload.tenant_access_group_ids
        expect(persisted.values.flatten).not_to include('samedis-care/devices.reader')
        expect(persisted[tenant.id.to_s]).to eq([group.id.to_s])
      end
    end
  end

  describe 'Actor.tenant_collection' do
    let!(:tenant) { Actors::Tenant.create!(name: "candos-type-tenant-#{sfx}") }

    after do
      # Actors::Tenant.create! auto-creates a default `organization` child via
      # ensure_defaults!; tenant.delete skips before_destroy :destroy_children,
      # so that child (and anything under it) is orphaned unless swept up here
      # -- same convention as spec/models/user_set_access_group_ids_spec.rb.
      Actor.where(:parent_ids.in => [tenant.id]).delete_all
      tenant.delete
    end

    it 'returns the real candos array for a well-formed Hash cache' do
      user.set(tenant_candos_cached: { tenant.id.to_s => ['samedis-care/x.read'] }, tenant_candos_cached_at: Time.now)

      entry = Actors::Tenant.where(_id: tenant.id).tenant_collection(user.reload).first
      expect(entry[:candos]).to eq(['samedis-care/x.read'])
    end

    it 'does not raise, and degrades to [], when #candos itself returns a non-Hash' do
      # #candos's own cache-invalidity check (user.rb:700) now heals a
      # persisted stray Array before it would ever reach here, so exercise
      # this guard directly rather than through a state that self-heals.
      allow(user).to receive(:candos).and_return([])

      result = nil
      expect { result = Actors::Tenant.where(_id: tenant.id).tenant_collection(user) }.not_to raise_error

      expect(result.first[:candos]).to eq([])
    end

    it 'normalizes a Hash cache missing this tenant\'s key to [] rather than nil' do
      user.set(tenant_candos_cached: { 'some-other-tenant-id' => ['x'] }, tenant_candos_cached_at: Time.now)

      entry = Actors::Tenant.where(_id: tenant.id).tenant_collection(user.reload).first
      expect(entry[:candos]).to eq([])
    end
  end

  # global_candos is the only other caller of User#candos besides
  # Actor.tenant_collection -- it needs the same two guards, or this fix's
  # benefit is silently undone for AppUserSerializer's top-level `candos`.
  describe 'User#global_candos' do
    it 'raises instead of masking a genuine aggregation failure as no candos' do
      allow(Actors::Mapping).to receive(:get_tenant_candos).and_raise(Mongo::Error::SocketTimeoutError, 'boom')

      expect { user.global_candos }.to raise_error(Mongo::Error::SocketTimeoutError)
    end

    it 'does not raise, and degrades to [], when #candos itself returns a non-Hash' do
      # Same reasoning as the tenant_collection guard above: the
      # cache-invalidity check now heals a persisted stray Array before it
      # reaches here, so exercise this guard directly.
      allow(user).to receive(:candos).and_return([])

      expect { expect(user.global_candos).to eq([]) }.not_to raise_error
    end
  end
end
