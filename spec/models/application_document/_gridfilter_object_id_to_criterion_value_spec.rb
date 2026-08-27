require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: adds `filterType: object_id` support,
# ported 1:1 from samedis-care-backend's newer gridfilter implementation.
RSpec.describe ApplicationDocument, '._gridfilter_object_id_to_criterion_value' do
  let(:oid) { BSON::ObjectId.new }
  let(:other_oid) { BSON::ObjectId.new }

  it 'equals returns the raw ObjectId' do
    expect(described_class._gridfilter_object_id_to_criterion_value('equals', oid.to_s)).to eq(oid)
  end

  it 'not_equal returns a $ne selector' do
    expect(described_class._gridfilter_object_id_to_criterion_value('not_equal', oid.to_s)).to eq('$ne' => oid)
  end

  it 'in_set coerces every element to an ObjectId' do
    result = described_class._gridfilter_object_id_to_criterion_value('in_set', [oid.to_s, other_oid.to_s])
    expect(result[:'$in']).to contain_exactly(oid, other_oid)
  end

  it 'not_in_set coerces every element to an ObjectId' do
    result = described_class._gridfilter_object_id_to_criterion_value('not_in_set', [oid.to_s, other_oid.to_s])
    expect(result[:'$nin']).to contain_exactly(oid, other_oid)
  end

  it 'greater_than returns a $gt selector' do
    expect(described_class._gridfilter_object_id_to_criterion_value('greater_than', oid.to_s)).to eq('$gt' => oid)
  end

  it 'less_than_or_equal returns a $lte selector' do
    expect(described_class._gridfilter_object_id_to_criterion_value('less_than_or_equal', 
                                                                    oid.to_s)).to eq('$lte' => oid)
  end

  it 'empty returns a $eq nil selector' do
    expect(described_class._gridfilter_object_id_to_criterion_value('empty', nil)).to eq('$eq': nil)
  end

  it 'not_empty returns a $ne nil selector' do
    expect(described_class._gridfilter_object_id_to_criterion_value('not_empty', nil)).to eq('$ne': nil)
  end

  it 'raises GridfilterError for an unsupported condition_type' do
    expect { described_class._gridfilter_object_id_to_criterion_value('contains', oid.to_s) }
      .to raise_error(ApplicationDocument::GridfilterError, /unsupported condition_type/)
  end
end
