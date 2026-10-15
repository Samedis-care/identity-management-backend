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

  # Samedis-care/samedis-care-issues#3297: the new paths are checked BEFORE the $merge, so a
  # collision leaves every path of the subtree untouched (the $merge alone left the documents
  # processed before the conflict rewritten and the rest not)
  describe 'all-or-nothing rebuild' do
    let(:new_name) { "renamed-#{sfx}" }

    def subtree_paths
      Actor.collection.find('$or' => [{ _id: tenant.id }, { parent_ids: tenant.id }]).to_h { [_1['_id'], _1['path']] }
    end

    context 'when orphaned mappings would collapse onto one path' do
      before do
        group_a.map_into!(user_actor)
        group_b.map_into!(user_actor)
        Actor.collection.delete_many(_id: { '$in' => [group_a.id, group_b.id] })
      end

      it 'rewrites no path at all, neither the colliding mappings nor the healthy rest of the subtree' do
        before_paths = subtree_paths

        expect { tenant.update!(name: new_name) }.to raise_error(Actor::PathCollisionError)

        expect(subtree_paths).to eq(before_paths)
      end

      it 'still names the colliding actors' do
        ids = mapping_ids

        expect { tenant.update!(name: new_name) }.to raise_error(Actor::PathCollisionError) do |e|
          expect(e.collisions.flat_map { _1[:ids] }).to match_array(ids.map(&:to_s))
        end
      end
    end

    context 'when an actor OUTSIDE the subtree already holds the new (name, path)' do
      let(:outside_id) { BSON::ObjectId.new }

      before do
        group_a.map_into!(user_actor)
        # the path the mapping below group_a would get after the rename
        target = [new_name, organization.name, tenant_profiles.name, group_a.name, email].join(' / ')
        Actor.collection.insert_one('_id' => outside_id, '_type' => 'Actors::Mapping', 'name' => email,
                                    'deleted' => false, 'parent_ids' => [], 'path' => target)
      end

      after { Actor.collection.delete_many(_id: outside_id) }

      it 'refuses the rebuild before writing anything, and names the outside holder too' do
        before_paths = subtree_paths

        expect { tenant.update!(name: new_name) }.to raise_error(Actor::PathCollisionError) do |e|
          expect(e.collisions.flat_map { _1[:ids] }).to include(outside_id.to_s, *mapping_ids.map(&:to_s))
        end
        expect(subtree_paths).to eq(before_paths)
      end
    end

    context 'when the unique index rejects the $merge after a clean check (a concurrent write)' do
      before do
        group_a.map_into!(user_actor)
        group_b.map_into!(user_actor)
        Actor.collection.delete_many(_id: { '$in' => [group_a.id, group_b.id] })
        calls = 0
        # the first call is the check before the $merge: let it see nothing, so the $merge runs
        allow(Actor).to receive(:path_rebuild_collisions).and_wrap_original do |original, *args|
          (calls += 1).eql?(1) ? [] : original.call(*args)
        end
      end

      it 'still reports the collision instead of a bare E11000' do
        expect { tenant.update!(name: new_name) }.to raise_error(Actor::PathCollisionError) do |e|
          expect(e.collisions.flat_map { _1[:ids] }).to match_array(mapping_ids.map(&:to_s))
        end
      end
    end

    # review of the first version: the query for holders outside the subtree filtered on path alone,
    # and no index starts with path, so every rebuild read every undeleted actor of every tenant
    describe 'the query for holders outside the subtree' do
      let(:holder_queries) { [] }

      before do
        queries = holder_queries
        allow_any_instance_of(Mongo::Collection).to receive(:find).and_wrap_original do |original, filter = {}, *rest|
          queries << filter if filter.is_a?(Hash) && filter[:_id].is_a?(Hash) && filter[:_id].key?('$nin')
          original.call(filter, *rest)
        end
      end

      it 'is bounded by name as well, so it can use the {name, path} index' do
        group_a.map_into!(user_actor)
        tenant.update!(name: new_name)

        expect(holder_queries).not_to be_empty
        expect(holder_queries).to all(include(name: { '$in' => be_an(Array) }))
        expect(holder_queries.flat_map { _1[:name]['$in'] }).to include(email)
      end

      it 'is not made at all when no actor of the set is undeleted' do
        Actor.collection.update_many({ '$or' => [{ _id: tenant.id }, { parent_ids: tenant.id }] }, '$set' => { deleted: true })

        expect { Actors::Tenant.where('$or': [{ _id: tenant.id }, { parent_ids: tenant.id }]).merge_rebuild_path! }.not_to raise_error
        expect(holder_queries).to be_empty
      end
    end

    context 'without any collision' do
      it 'rewrites the paths of the whole subtree' do
        group_a.map_into!(user_actor)
        tenant.update!(name: new_name)

        paths = subtree_paths
        expect(paths.values).to all(start_with(new_name))
        expect(paths[organization.id]).to eq([new_name, organization.name].join(' / '))
      end
    end
  end
end
