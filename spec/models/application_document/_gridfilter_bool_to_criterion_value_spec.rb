require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: ported 1:1 from samedis-care-backend's
# _gridfilter_bool_to_criterion_value. Nil/unset documents only fold into the
# matching side of the comparison when the field's own Mongoid `default:` says
# what unset means - a field with no declared default keeps the original,
# strict true/false selector (see Actor#gender-style tri-state fields).
RSpec.describe ApplicationDocument, '._gridfilter_bool_to_criterion_value' do
  describe 'field with default: false (Actor#auto)' do
    let(:field) { :auto }

    it 'equals true matches only explicit true' do
      expect(Actor._gridfilter_bool_to_criterion_value('equals', 'true', field: field)).to be(true)
    end

    it 'equals false folds nil/unset into the match' do
      expect(Actor._gridfilter_bool_to_criterion_value('equals', 'false', field: field)).to eq('$in' => [false, nil])
    end

    it 'not_equal true folds nil/unset into the match' do
      expect(Actor._gridfilter_bool_to_criterion_value('not_equal', 'true', field: field)).to eq('$in' => [false, nil])
    end

    it 'not_equal false matches only explicit true' do
      expect(Actor._gridfilter_bool_to_criterion_value('not_equal', 'false', field: field)).to be(true)
    end
  end

  describe 'field with default: true (Actor#active)' do
    let(:field) { :active }

    it 'equals true folds nil/unset into the match (unset legacy record is semantically active)' do
      expect(Actor._gridfilter_bool_to_criterion_value('equals', 'true', field: field)).to eq('$in' => [true, nil])
    end

    it 'equals false matches only explicit false' do
      expect(Actor._gridfilter_bool_to_criterion_value('equals', 'false', field: field)).to be(false)
    end

    it 'not_equal true matches only explicit false - must NOT fold in nil here' do
      expect(Actor._gridfilter_bool_to_criterion_value('not_equal', 'true', field: field)).to be(false)
    end

    it 'not_equal false folds nil/unset into the match' do
      expect(Actor._gridfilter_bool_to_criterion_value('not_equal', 'false', field: field)).to eq('$in' => [true, nil])
    end
  end

  describe 'no field / field with no declared default' do
    it 'equals true is bare truthy with no fold' do
      expect(described_class._gridfilter_bool_to_criterion_value('equals', 'true')).to be(true)
    end

    it 'equals false is bare falsy with no fold' do
      expect(described_class._gridfilter_bool_to_criterion_value('equals', 'false')).to be(false)
    end
  end

  describe 'before_today / after_today / before_now / after_now' do
    it 'before_today true resolves to a $lt selector anchored on today' do
      result = Actor._gridfilter_bool_to_criterion_value('before_today', 'true')
      expect(result).to match('$lt' => have_attributes(to_date: Time.zone.today))
    end

    it 'after_today false resolves to the same $lt selector as before_today true (negated)' do
      result = Actor._gridfilter_bool_to_criterion_value('after_today', 'false')
      expect(result).to match('$lt' => have_attributes(to_date: Time.zone.today))
    end
  end

  it 'raises GridfilterError for an unparseable value' do
    expect { Actor._gridfilter_bool_to_criterion_value('equals', 'maybe') }
      .to raise_error(ApplicationDocument::GridfilterError, %r{accepted: true/yes or false/no})
  end

  it 'raises GridfilterError for an unsupported condition_type' do
    expect { Actor._gridfilter_bool_to_criterion_value('contains', 'true') }
      .to raise_error(ApplicationDocument::GridfilterError, /unsupported condition_type/)
  end
end
