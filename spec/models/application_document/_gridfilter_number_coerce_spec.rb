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

  # Regression guard for review round 4 on PR #284: `"abc".to_i` is silently 0, not
  # an error - a garbage-text filter value used to build a valid-looking comparison
  # against 0 instead of raising, and on a field with a numeric default (like
  # sign_in_count, default: 0) the nil-fold made it worse: "greater than 'abc'"
  # would return every row that never set the field, reachable from the Contents
  # grid's plain TextField for a "number" filterType column.
  it 'raises GridfilterError for a non-numeric String, rather than silently coercing it to 0' do
    expect { User._gridfilter_number_coerce('abc', field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /invalid numeric filter value/)
  end

  # Regression guard for review round 5 on PR #284: a digit string this long
  # overflows BSON's 64-bit int/long serializer ("9"*100 -> RangeError: bignum
  # too big to convert into 'long long') at query send time - unrescued, an
  # HTTP 500. Not a regression (main has the identical crash via Mongoid's own
  # String-to-Integer evolution), but this line is now the one place that
  # decides what a numeric filter value may be, so it's the place to bound it.
  it 'raises GridfilterError for a digit string too large for a 64-bit int' do
    expect { User._gridfilter_number_coerce('9' * 30, field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /invalid numeric filter value/)
  end

  it 'still accepts the largest valid 64-bit int' do
    max_int64 = (2**63 - 1).to_s
    expect(User._gridfilter_number_coerce(max_int64, field: :sign_in_count)).to eq(2**63 - 1)
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

    # Unlike the scalar coercion (which raises - there's exactly one value to fail
    # on), a non-numeric String set element is dropped like any other garbage
    # element here: there's no single required value, so excluding one bad element
    # from an otherwise-valid set is more useful than rejecting the whole request.
    it 'passes a non-numeric String element through unchanged too, rather than coercing it to 0' do
      expect(User._gridfilter_number_coerce_set_element('abc', field: :sign_in_count)).to eq('abc')
    end

    it 'passes a too-large digit string through unchanged too, rather than crashing at BSON serialization' do
      too_big = '9' * 30
      expect(User._gridfilter_number_coerce_set_element(too_big, field: :sign_in_count)).to eq(too_big)
    end
  end
end
