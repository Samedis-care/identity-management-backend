require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: ported 1:1 from samedis-care-backend's
# _gridfilter_number_to_criterion_value. nil/unset documents only fold into
# the matching side when the field declares a numeric default - a field with
# no declared default keeps the original, strict numeric selector.
RSpec.describe ApplicationDocument, '._gridfilter_number_to_criterion_value' do
  describe 'field with default: 0 (User#sign_in_count)' do
    let(:field) { :sign_in_count }

    it 'equals 0 folds nil/unset into the match' do
      result = User._gridfilter_number_to_criterion_value('equals', 0, nil, field: field)
      expect(result).to eq([[{ '$eq' => 0 }, { '$eq' => nil }], '$or'])
    end

    it 'equals 5 does not fold nil' do
      expect(User._gridfilter_number_to_criterion_value('equals', 5, nil, field: field)).to eq('$eq' => 5)
    end

    it 'less_than 1 folds nil/unset into the match (0 < 1)' do
      result = User._gridfilter_number_to_criterion_value('less_than', 1, nil, field: field)
      expect(result).to eq([[{ '$lt' => 1 }, { '$eq' => nil }], '$or'])
    end

    it 'greater_than 0 does not fold nil (0 is not > 0)' do
      expect(User._gridfilter_number_to_criterion_value('greater_than', 0, nil, field: field)).to eq('$gt' => 0)
    end

    it 'not_equal 0 folds nil/unset with $and/$ne' do
      result = User._gridfilter_number_to_criterion_value('not_equal', 0, nil, field: field)
      expect(result).to eq([[{ '$ne' => 0 }, { '$ne' => nil }], '$and'])
    end

    it 'in_set including 0 adds nil to the $in list instead of a wrapping $or' do
      result = User._gridfilter_number_to_criterion_value('in_set', [0, 3], nil, field: field)
      expect(result[:'$in']).to contain_exactly(0, 3, nil)
    end
  end

  describe 'field with no declared default (User#gender)' do
    let(:field) { :gender }

    it 'equals 0 does not fold nil - no declared default means nil semantics are unknown' do
      expect(User._gridfilter_number_to_criterion_value('equals', 0, nil, field: field)).to eq('$eq' => 0)
    end
  end

  it 'in_range requires a filterTo' do
    expect { described_class._gridfilter_number_to_criterion_value('in_range', 1, nil) }
      .to raise_error(ApplicationDocument::GridfilterError, /missing condition filterTo/)
  end

  it 'raises GridfilterError for an unsupported condition_type' do
    expect { described_class._gridfilter_number_to_criterion_value('contains', 1, nil) }
      .to raise_error(ApplicationDocument::GridfilterError, /unsupported condition_type/)
  end
end
