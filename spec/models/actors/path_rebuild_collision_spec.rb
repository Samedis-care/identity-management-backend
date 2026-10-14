require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#3160: Actor.merge_rebuild_path!
# failed with a bare E11000 (reported as "Datenbankfehler") when two mappings of the
# same user lost their parent actors, collapsed onto the same (name, path) and hit the
# unique index actor_path_unique_undeleted.
RSpec.describe Actor, '.merge_rebuild_path! with colliding paths' do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "pathcollision-#{sfx}@path-collision-spec.test" }

  let!(:tenant) { Actors::Tenant.create!(name: "path-collision-tenant-#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:group_a) { Actors::Group.create!(name: "group-a-#{sfx}", parent: tenant_profiles, system: true) }
  let!(:group_b) { Actors::Group.create!(name: "group-b-#{sfx}", parent: tenant_profiles, system: true) }

  let!(:user) do
    User.new(
      email: email,
      email_confirmation: email,
      first_name: 'Path',
      last_name: 'Collision',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    ).tap do |u|
      u.skip_confirmation!
      u.save!
    end
  end
  let!(:user_actor) { user.actor }

  # The test database is not guaranteed to carry the production unique index
  # (db:mongoid:create_indexes is not part of the spec setup), so create it here
  # and drop it again only if this spec created it.
  let(:index_name) { 'actor_path_unique_undeleted' }

  before do
    @created_index = Actor.collection.indexes.none? { _1['name'] == index_name }
    if @created_index
      Actor.collection.indexes.create_one(
        { name: 1, path: 1 },
        unique: true, name: index_name, partial_filter_expression: { deleted: false }
      )
    end
  end

  after do
    Actors::Mapping.where(map_actor: user_actor).delete_all
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    user_actor&.delete
    user.delete
    tenant.delete
    Actor.collection.indexes.drop_one(index_name) if @created_index
  end

  def mapping_ids
    Actors::Mapping.where(map_actor: user_actor, deleted: false).pluck(:id)
  end

  it 'rebuilds a healthy subtree without raising' do
    group_a.map_into!(user_actor)
    group_b.map_into!(user_actor)

    expect { tenant.rebuild_path! }.not_to raise_error
  end

  context 'when both parent groups of two mappings no longer exist' do
    before do
      group_a.map_into!(user_actor)
      group_b.map_into!(user_actor)
      # simulates the orphaning seen in production: parents removed without their mappings
      Actor.collection.delete_many(_id: { '$in' => [group_a.id, group_b.id] })
    end

    it 'raises PathCollisionError naming the colliding actors instead of a bare E11000' do
      ids = mapping_ids
      expect(ids.size).to eq(2)

      expect { Actor.where(:_id.in => ids).merge_rebuild_path! }.to raise_error(Actor::PathCollisionError) do |e|
        expect(e.collisions.size).to eq(1)
        expect(e.collisions.first[:name]).to eq(email)
        expect(e.collisions.first[:ids]).to match_array(ids.map(&:to_s))
        expect(e.message).to include(email)
        expect(e.message).to include(ids.first.to_s)
      end
    end

    it 'does not turn unrelated database errors into PathCollisionError' do
      collection = Actor.collection
      allow(Actor).to receive(:collection).and_return(collection)
      allow(collection).to receive(:aggregate).and_raise(Mongo::Error::OperationFailure.new('some other failure'))

      expect { Actor.where(:_id.in => mapping_ids).merge_rebuild_path! }
        .to raise_error(Mongo::Error::OperationFailure, /some other failure/)
    end
  end
end
