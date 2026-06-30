require 'rails_helper'
require Rails.root.join('lib/apac_migration/leak_guard')
require Rails.root.join('lib/apac_migration/tenant_set_resolver')

RSpec.describe ApacMigration::LeakGuard do
  let(:apac_id) { BSON::ObjectId.new }
  let(:resolver) { instance_double(ApacMigration::TenantSetResolver, apac_tenant_ids: [apac_id]) }

  # Builds a fake Mongo::Client where each collection's #find(...).first
  # returns the configured offending document (or nil = clean).
  def fake_client(actors: nil, invites: nil, users: nil)
    collections = {
      'actors'  => double(find: double(first: actors)),
      'invites' => double(find: double(first: invites)),
      'users'   => double(find: double(first: users))
    }
    double('target_client').tap do |client|
      allow(client).to receive(:[]) { |name| collections.fetch(name) }
    end
  end

  it 'passes when nothing leaks' do
    expect { described_class.new(resolver).assert!(fake_client) }.not_to raise_error
  end

  it 'fails on a mapping with a non-APAC tenant_id' do
    leaking = { '_id' => BSON::ObjectId.new, 'tenant_id' => BSON::ObjectId.new }
    expect { described_class.new(resolver).assert!(fake_client(actors: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end

  it 'fails on an invite with a non-APAC tenant_id' do
    leaking = { '_id' => BSON::ObjectId.new, 'tenant_id' => BSON::ObjectId.new.to_s }
    expect { described_class.new(resolver).assert!(fake_client(invites: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end

  it 'fails on a user that still carries EU cache fields' do
    leaking = { '_id' => BSON::ObjectId.new, 'tenants_cached' => [BSON::ObjectId.new] }
    expect { described_class.new(resolver).assert!(fake_client(users: leaking)) }
      .to raise_error(/LEAK GUARD FAILED/i)
  end
end
