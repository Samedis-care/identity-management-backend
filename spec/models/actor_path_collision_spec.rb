require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3160.
#
# after_save :rebuild_path! rewrites the path of an actor and all its descendants with one
# $merge. Orphaned Actors::Mapping docs (parent actor no longer exists) lose that parent's
# segment, so two mappings of the same user collapse onto the same (name, path) and the
# partial unique index actor_path_unique_undeleted rejects the $merge. That used to surface as
# a raw Mongo::Error::OperationFailure ("Datenbankfehler" in the frontend).
#
# The test database has no Mongoid indexes created, so the one this is about is created for
# the duration of the spec and dropped again afterwards.
RSpec.describe Actor, 'path collision on rebuild' do
  INDEX_NAME = 'actor_path_unique_undeleted'.freeze

  before(:all) do
    Actor.collection.indexes.create_one(
      { name: 1, path: 1 },
      unique: true, name: INDEX_NAME, partial_filter_expression: { deleted: false }
    )
  end

  after(:all) do
    Actor.collection.indexes.drop_one(INDEX_NAME)
  end

  let(:sfx) { SecureRandom.hex(4) }
  let!(:tenant) { Actors::Tenant.create!(name: "collide-#{sfx}") }
  let(:missing_parent_ids) { [BSON::ObjectId.new, BSON::ObjectId.new] }
  let(:mapping_ids) { [BSON::ObjectId.new, BSON::ObjectId.new] }
  let(:mapping_name) { "user-#{sfx}@collide.test" }

  # two mappings of one user whose parents are gone: distinct stored paths, equal rebuilt path
  def insert_orphan_mappings
    mapping_ids.zip(missing_parent_ids).each_with_index do |(id, missing), index|
      Actor.collection.insert_one(
        '_id' => id, '_type' => 'Actors::Mapping', 'name' => mapping_name, 'deleted' => false,
        'parent_ids' => [tenant.id, missing], 'path' => "old-#{index} / #{mapping_name}"
      )
    end
  end

  after do
    Actor.collection.delete_many('_id' => { '$in' => mapping_ids })
    Actor.collection.delete_many('_id' => tenant.id)
  end

  context 'when orphaned mappings would collapse onto one path' do
    before { insert_orphan_mappings }

    it 'raises PathCollisionError instead of the raw database error' do
      expect { tenant.update!(name: "renamed-#{sfx}") }.to raise_error(Actor::PathCollisionError)
    end

    it 'names the colliding actors and the path' do
      error = begin
        tenant.update!(name: "renamed-#{sfx}")
      rescue Actor::PathCollisionError => e
        e
      end

      expect(error.name).to eq(mapping_name)
      expect(error.path).to eq("renamed-#{sfx} / #{mapping_name}")
      expect(error.actor_ids).to match_array(mapping_ids)
      expect(error.message).to include(mapping_ids.first.to_s, mapping_ids.last.to_s, error.path)
    end

    it 'does not hide other database errors' do
      other = Mongo::Error::OperationFailure.new('E11000 duplicate key error collection: x index: some_other_index dup key')
      allow_any_instance_of(Mongo::Collection).to receive(:aggregate).and_raise(other)

      expect { tenant.update!(name: "other-#{sfx}") }.to raise_error(Mongo::Error::OperationFailure)
    end
  end

  context 'without orphaned mappings' do
    it 'still renames the tenant and rewrites its path' do
      tenant.update!(name: "fine-#{sfx}")

      expect(Actor.where(_id: tenant.id).first.path).to eq("fine-#{sfx}")
    end
  end
end
