require 'rails_helper'
require Rails.root.join('lib/apac_migration/leak_guard')
require Rails.root.join('lib/apac_migration/tenant_set_resolver')

RSpec.describe ApacMigration::LeakGuard do
  let(:eu_id) { BSON::ObjectId.new }
  let(:resolver) { instance_double(ApacMigration::TenantSetResolver, eu_tenant_ids: [eu_id]) }

  # Fake Mongo client that evaluates the small query subset the leak guard uses
  # ($in / $nin / $or / scalar equality) against in-memory docs, so the
  # EU-blacklist behaviour (native APAC records ignored, EU refs flagged) is
  # really exercised. #find returns the matched docs (responds to #first and
  # #find{} like a Mongo::Collection::View).
  def fake_client(actors: [], invites: [], users: [])
    data = { 'actors' => Array.wrap(actors), 'invites' => Array.wrap(invites), 'users' => Array.wrap(users) }
    client = double('target_client')
    allow(client).to receive(:[]) do |name|
      docs = data.fetch(name)
      collection = double("#{name}_collection")
      allow(collection).to receive(:find) do |query, _opts = nil|
        docs.select { |doc| matches?(doc, query) }
      end
      collection
    end
    client
  end

  def matches?(doc, query)
    query.all? do |field, condition|
      if field == '$or'
        condition.any? { |sub| matches?(doc, sub) }
      elsif condition.is_a?(Hash) && condition.key?('$in')
        values = doc[field].is_a?(Array) ? doc[field] : [doc[field]]
        values.any? { |v| condition['$in'].include?(v) }
      elsif condition.is_a?(Hash) && condition.key?('$nin')
        !condition['$nin'].include?(doc[field])
      else
        doc[field] == condition
      end
    end
  end

  it 'passes when only native APAC records are present (no EU tenant refs)' do
    native_map  = { '_id' => BSON::ObjectId.new, '_type' => 'Actors::Mapping', 'tenant_id' => BSON::ObjectId.new }
    native_user = {
      '_id' => BSON::ObjectId.new,
      'tenants_cached' => [BSON::ObjectId.new],
      'tenant_access_group_ids' => { BSON::ObjectId.new.to_s => ['g1'] } # native tenant key, not EU
    }
    expect { described_class.new(resolver).assert!(fake_client(actors: native_map, users: native_user)) }
      .not_to raise_error
  end

  it 'fails on a mapping pointing at an EU source tenant' do
    leaking = { '_id' => BSON::ObjectId.new, '_type' => 'Actors::Mapping', 'tenant_id' => eu_id }
    expect { described_class.new(resolver).assert!(fake_client(actors: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end

  it 'fails on an EU source tenant present on the target' do
    leaking = { '_id' => eu_id, '_type' => 'Actors::Tenant' }
    expect { described_class.new(resolver).assert!(fake_client(actors: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end

  it 'fails on an invite belonging to an EU source tenant (string form)' do
    leaking = { '_id' => BSON::ObjectId.new, 'tenant_id' => eu_id.to_s }
    expect { described_class.new(resolver).assert!(fake_client(invites: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end

  it 'fails on a user caching an EU source tenant in tenants_cached' do
    leaking = { '_id' => BSON::ObjectId.new, 'tenants_cached' => [eu_id] }
    expect { described_class.new(resolver).assert!(fake_client(users: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end

  it 'fails on a user with an EU tenant id as a cache hash KEY' do
    leaking = { '_id' => BSON::ObjectId.new, 'tenant_access_group_ids' => { eu_id.to_s => ['g1'] } }
    expect { described_class.new(resolver).assert!(fake_client(users: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end
end
