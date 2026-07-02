require 'rails_helper'
require Rails.root.join('lib/apac_migration/mongo_copier')

RSpec.describe ApacMigration::MongoCopier do
  let(:copier) { described_class.new }

  # A plain Array stands in for a Mongo::Collection::View — both respond to
  # #each_slice via Enumerable, which is all MongoCopier#copy needs.
  def fake_model(name, docs)
    collection = double("#{name}_collection", name: name)
    allow(collection).to receive(:find).and_return(docs)
    double(name, collection: collection)
  end

  def bulk_write_error(index:, errmsg:)
    result = { 'writeErrors' => [{ 'index' => index, 'code' => 11_000, 'errmsg' => errmsg }] }
    Mongo::Error::BulkWriteError.new(result)
  end

  describe '#copy' do
    it 'continues past a batch failure: reports the count, records the error, does not raise' do
      docs = [
        { '_id' => BSON::ObjectId.new, 'name' => 'ok-doc', 'path' => 'a/ok-doc' },
        { '_id' => BSON::ObjectId.new, 'name' => 'system', 'path' => 'apps/identity-management/tenants/system' }
      ]
      model = fake_model('actors', docs)

      error = bulk_write_error(index: 1, errmsg: 'E11000 duplicate key')
      target_collection = double('target_actors')
      allow(target_collection).to receive(:bulk_write).and_raise(error)
      target_client = double('target_client')
      allow(target_client).to receive(:[]).with('actors').and_return(target_collection)
      allow(copier).to receive(:target_client).and_return(target_client)

      total = nil
      expect { total = copier.copy(model: model, selector: {}, label: 'actors') }.not_to raise_error

      expect(total).to eq(2)
      expect(copier.errors.size).to eq(1)
      expect(copier.errors.first).to include(
        collection: 'actors',
        id: docs[1]['_id'],
        name: 'system',
        path: 'apps/identity-management/tenants/system',
        message: 'E11000 duplicate key'
      )
    end

    it 'records nothing when the batch succeeds' do
      docs = [{ '_id' => BSON::ObjectId.new, 'name' => 'fine' }]
      model = fake_model('actors', docs)

      target_collection = double('target_actors')
      allow(target_collection).to receive(:bulk_write).and_return(true)
      target_client = double('target_client')
      allow(target_client).to receive(:[]).with('actors').and_return(target_collection)
      allow(copier).to receive(:target_client).and_return(target_client)

      copier.copy(model: model, selector: {}, label: 'actors')
      expect(copier.errors).to be_empty
    end
  end
end
