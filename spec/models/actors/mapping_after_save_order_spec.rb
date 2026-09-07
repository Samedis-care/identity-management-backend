require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2675: a newly invited
# user's tenant permissions were intermittently invisible to a separately
# minted token. Root cause: Actors::Mapping's after_save chain invalidated the
# mapped user's caches (#user_cache_expire!) BEFORE writing this mapping's own
# cando cache (#merge_group_candos!) — the reverse of every other place in
# this codebase that performs the same pair of operations (Actor#merge_group_
# candos! and Role#update_group_candos! both merge first, expire second). A
# User#candos recompute racing the window between the two callbacks aggregated
# over a still-blank cached_candos and persisted (and, via
# Actor.tenant_collection, permanently snapshotted into tenants_cached) an
# empty cando set for that tenant.
RSpec.describe Actors::Mapping, '#after_save callback order' do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "cacheorder-#{sfx}@mapping-order-spec.test" }

  # A self-contained App, rather than depending on a seeded 'identity-management'
  # record being present in whatever database the spec suite runs against.
  let!(:app) { Actors::App.create!(name: "cache-order-app-#{sfx}") }
  let!(:functionality) do
    Functionality.create!(
      app: app.name,
      module: "cacheordertest#{sfx}",
      ident: 'reader',
      title: 'Cache Order Test',
      description: 'Cache Order Test'
    )
  end
  let!(:role) do
    Role.create!(name: "cache-order-role-#{sfx}", app: app.name, functionality_ids: [functionality.id])
  end

  let!(:tenant) { Actors::Tenant.create!(name: "cache-order-tenant-#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:group) do
    Actors::Group.create!(name: "cache-order-group-#{sfx}", parent: tenant_profiles, system: true, role_ids: [role.id])
  end

  let!(:user) do
    User.new(
      email: email,
      email_confirmation: email,
      first_name: 'Cache',
      last_name: 'Order',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  after do
    described_class.where(map_actor: user_actor).delete_all
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    user_actor&.delete
    user.delete
    tenant.delete
    role.delete
    functionality.delete
    app.delete
  end

  it 'has this mapping\'s cached_candos already merged by the time the mapped user\'s cache is invalidated' do
    concurrent_read = nil

    # Stubs the SECOND callback in the (fixed) chain to simulate a concurrent
    # request's User#candos recompute landing exactly between the two
    # after_save callbacks -- the window this bug lived in. Before the fix,
    # user_cache_expire! ran FIRST, so this same stub point would have fired
    # before cached_candos was written, and the concurrent read below would
    # have found it blank.
    allow_any_instance_of(described_class).to receive(:user_cache_expire!).and_wrap_original do |m, *a|
      concurrent_read = User.find(user.id).candos
      m.call(*a)
    end

    group.map_into!(user_actor)

    expect(concurrent_read).to be_a(Hash)
    expected_cando = "#{functionality.app}/#{functionality.module}.#{functionality.ident}"
    expect(concurrent_read.values.flatten).to include(expected_cando)
  end

  it 'still expires the mapped user\'s caches (the invalidation itself is not skipped)' do
    user.tap do |u|
      u.set(tenants_cached: [{ id: 'stale' }], tenants_cached_at: Time.now, tenant_candos_cached: { 'stale' => [] },
            tenant_candos_cached_at: Time.now)
    end

    group.map_into!(user_actor)

    fresh = User.find(user.id)
    expect(fresh.tenants_cached).to be_nil
    expect(fresh.tenant_candos_cached).to be_nil
  end
end
