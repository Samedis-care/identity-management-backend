require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: ported 1:1 from samedis-care-backend's
# _gridfilter_number_coerce / _gridfilter_number_coerce_set_element. A field's
# own declared Mongoid type decides String -> Integer/Float coercion, so a
# gridfilter value compares as the right type regardless of how it arrived.
RSpec.describe ApplicationDocument, '._gridfilter_number_coerce' do
  it 'coerces a numeric string to Integer for an Integer field' do
    expect(User._gridfilter_number_coerce('5', field: :sign_in_count)).to eq(5)
  end

  it 'truncates a Float value for an Integer field (bare JSON number vs Integer-typed field)' do
    expect(User._gridfilter_number_coerce(5.9, field: :sign_in_count)).to eq(5)
  end

  it 'passes nil through untouched' do
    expect(User._gridfilter_number_coerce(nil, field: :sign_in_count)).to be_nil
  end

  it 'raises GridfilterError for a non-numeric, non-string value' do
    expect { User._gridfilter_number_coerce({ a: 1 }, field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /invalid numeric filter value/)
  end

  describe '._gridfilter_number_coerce_set_element' do
    it 'coerces a valid element the same way as the scalar coercion' do
      expect(User._gridfilter_number_coerce_set_element('5', field: :sign_in_count)).to eq(5)
    end

    it 'preserves nil as a literal set element (does not become 0)' do
      expect(User._gridfilter_number_coerce_set_element(nil, field: :sign_in_count)).to be_nil
    end

    it 'passes a garbage element through unchanged instead of raising' do
      garbage = { a: 1 }
      expect(User._gridfilter_number_coerce_set_element(garbage, field: :sign_in_count)).to eq(garbage)
    end
  end
end
