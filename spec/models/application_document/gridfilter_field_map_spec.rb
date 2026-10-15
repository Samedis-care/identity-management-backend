require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2635: ApplicationDocument.gridfilter applied
# field_map (always id -> _id) BEFORE checking the whitelist, so User, whose gridfilter_fields has :id
# but not :_id, rejected every gridfilter on id with a GridfilterError (HTTP 400), although the
# generated docs list `id` as filterable and components-care's request batching always sends `id`.
RSpec.describe ApplicationDocument, '.gridfilter field whitelist and field_map' do
  let(:oid) { BSON::ObjectId.new }
  let(:other_oid) { BSON::ObjectId.new }
  let(:in_set) { { 'id' => { 'filterType' => 'object_id', 'type' => 'inSet', 'filter' => [oid.to_s, other_oid.to_s] } } }

  describe 'User, whose whitelist has id but not _id' do
    it 'accepts a gridfilter on id' do
      expect { User.gridfilter(in_set) }.not_to raise_error
    end

    it 'filters on _id, the field the criterion needs' do
      selector = User.gridfilter(in_set).selector.to_json

      expect(selector).to include('_id')
      expect(selector).to include(oid.to_s)
    end

    it 'accepts the same filter as a JSON string, the way the API receives it' do
      expect { User.gridfilter(in_set.to_json) }.not_to raise_error
    end

    it 'still filters on a whitelisted field' do
      expect(User.gridfilter('email' => { 'filterType' => 'text', 'type' => 'contains', 'filter' => 'x' }).selector).to be_present
    end

    it 'still rejects a field that is not whitelisted' do
      expect { User.gridfilter('encrypted_password' => { 'filterType' => 'text', 'type' => 'contains', 'filter' => 'x' }) }
        .to raise_error(ApplicationDocument::GridfilterError, /None of the provided fields is valid/)
    end

    it 'does not let an unwhitelisted field in through the id mapping' do
      expect { User.gridfilter('_id' => { 'filterType' => 'object_id', 'type' => 'inSet', 'filter' => [oid.to_s] }) }
        .to raise_error(ApplicationDocument::GridfilterError)
    end

    it 'applies a combination of a whitelisted id and a field that is not whitelisted by dropping only the latter' do
      filters = in_set.merge('encrypted_password' => { 'filterType' => 'text', 'type' => 'contains', 'filter' => 'x' })

      expect(User.gridfilter(filters).selector.to_json).not_to include('encrypted_password')
    end
  end

  describe 'a model with the default whitelist (all fields, which includes _id)' do
    it 'still accepts a gridfilter on id' do
      expect { Actor.gridfilter(in_set) }.not_to raise_error
      expect(Actor.gridfilter(in_set).selector.to_json).to include(oid.to_s)
    end
  end

  describe 'a per-model alias from set_field_map' do
    # stubs, not Class.new(EmailBlacklist): on Mongoid 9.1 a subclass adds a _type field to the root class
    # for the rest of the process, and the suite runs in random order
    before do
      allow(EmailBlacklist).to receive(:gridfilter_fields).and_return(%i[blocked])
      allow(EmailBlacklist).to receive(:field_map).and_return({ id: :_id, blocked: :domain })
    end

    it 'accepts a whitelisted alias and filters on the field it maps to' do
      filters = { 'blocked' => { 'filterType' => 'text', 'type' => 'contains', 'filter' => 'x' } }

      expect(EmailBlacklist.gridfilter(filters).selector.to_json).to include('domain')
    end

    it 'still rejects the mapped field when only the alias is whitelisted' do
      filters = { 'domain' => { 'filterType' => 'text', 'type' => 'contains', 'filter' => 'x' } }

      expect { EmailBlacklist.gridfilter(filters) }.to raise_error(ApplicationDocument::GridfilterError)
    end

    it 'does not add a _type field to the real model (what defining a subclass here would do)' do
      expect(EmailBlacklist.fields.keys).not_to include('_type')
    end
  end
end
