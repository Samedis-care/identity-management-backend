require 'rails_helper'

RSpec.describe Actors::Tenant, type: :model do
  describe '#region_effective' do
    it 'treats nil as eu' do
      expect(described_class.new(region: nil).region_effective).to eq('eu')
    end

    it 'treats blank as eu' do
      expect(described_class.new(region: '').region_effective).to eq('eu')
    end

    it 'returns the explicit region otherwise' do
      expect(described_class.new(region: 'apac').region_effective).to eq('apac')
      expect(described_class.new(region: 'eu').region_effective).to eq('eu')
    end
  end

  describe '#apac?' do
    it 'is true only for the apac region' do
      expect(described_class.new(region: 'apac').apac?).to be(true)
      expect(described_class.new(region: 'eu').apac?).to be(false)
      expect(described_class.new(region: nil).apac?).to be(false)
    end
  end

  describe 'scopes' do
    let!(:apac_tenant) { described_class.create!(name: "apac_#{SecureRandom.hex(4)}", region: 'apac') }
    let!(:eu_tenant)   { described_class.create!(name: "eu_#{SecureRandom.hex(4)}", region: 'eu') }
    let!(:nil_tenant)  { described_class.create!(name: "nil_#{SecureRandom.hex(4)}", region: nil) }

    after { [apac_tenant, eu_tenant, nil_tenant].each(&:destroy) }

    it '.apac returns only apac tenants' do
      ids = described_class.apac.pluck(:_id)
      expect(ids).to include(apac_tenant.id)
      expect(ids).not_to include(eu_tenant.id, nil_tenant.id)
    end

    it '.eu returns eu and nil (default) tenants' do
      ids = described_class.eu.pluck(:_id)
      expect(ids).to include(eu_tenant.id, nil_tenant.id)
      expect(ids).not_to include(apac_tenant.id)
    end
  end
end
