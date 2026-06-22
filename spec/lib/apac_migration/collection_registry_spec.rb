require 'rails_helper'
require Rails.root.join('lib/apac_migration/collection_registry')

RSpec.describe ApacMigration::CollectionRegistry do
  before { Rails.application.eager_load! }

  describe '.assert_complete!' do
    it 'passes when every tenant-scoped collection is classified' do
      expect { described_class.assert_complete! }.not_to raise_error
    end

    it 'raises when a tenant-scoped collection is neither copied nor excluded' do
      allow(described_class).to receive(:tenant_scoped_collections)
        .and_return(described_class::COPIED.keys + %w[brand_new_tenant_thing])

      expect { described_class.assert_complete! }
        .to raise_error(/unreviewed tenant-scoped collection.*brand_new_tenant_thing/m)
    end
  end

  it 'never lists the same collection as both copied and excluded' do
    expect(described_class::COPIED.keys & described_class::EXCLUDED.keys).to be_empty
  end
end
