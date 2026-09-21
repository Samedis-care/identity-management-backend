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
  # String-to-Integer evolution), but a numeric filter value has to be one the
  # database can actually be asked about.
  #
  # The message changed with samedis-care-issues#2979, which moved the range
  # half of the check out of `_gridfilter_numeric_string?` and behind the
  # coercion: out of range is now reported as out of range, not as
  # not-a-number.
  it 'raises GridfilterError for a digit string too large for a 64-bit int' do
    expect { User._gridfilter_number_coerce('9' * 30, field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /numeric filter value out of range/)
  end

  # samedis-care-issues#2979, the case the old placement could not see:
  # `self.gridfilter` JSON.parses the filter param, so an unquoted number
  # arrives as a Ruby Integer and skipped the String-gated range check
  # entirely, reaching BSON as a Bignum.
  it 'raises GridfilterError for a bare (unquoted) JSON number beyond int64' do
    expect { User._gridfilter_number_coerce(10**30, field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /numeric filter value out of range/)
  end

  # `Float::INFINITY.to_i` raises FloatDomainError rather than yielding a
  # Bignum the range check could see, and FloatDomainError < RangeError, so it
  # reached the same `Exception` catch-all as a 500. Arrives from a bare JSON
  # number that overflows Float: `JSON.parse('[1e400]') == [Infinity]`.
  it 'raises GridfilterError for Float::INFINITY rather than FloatDomainError' do
    expect { User._gridfilter_number_coerce(Float::INFINITY, field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /numeric filter value out of range/)
  end

  it 'raises GridfilterError for NaN, which to_i also refuses' do
    expect { User._gridfilter_number_coerce(Float::NAN, field: :sign_in_count) }
      .to raise_error(ApplicationDocument::GridfilterError, /numeric filter value out of range/)
  end

  it 'still accepts the largest valid 64-bit int' do
    max_int64 = (2**63 - 1).to_s
    expect(User._gridfilter_number_coerce(max_int64, field: :sign_in_count)).to eq(2**63 - 1)
  end

  # The old check was `value.strip.to_i.abs <= 2**63 - 1`, and `(-2**63).abs`
  # is 2**63 - one past that bound - so the most negative int64 was rejected
  # even though BSON serializes it fine. Checking the coerced value against
  # the real range fixes that asymmetry as a side effect.
  it 'accepts the smallest valid 64-bit int, which the old .abs bound rejected' do
    min_int64 = (-2**63).to_s
    expect(User._gridfilter_number_coerce(min_int64, field: :sign_in_count)).to eq(-2**63)
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

    # BEHAVIOR CHANGE, samedis-care-issues#2979. This used to pass through
    # unchanged, to be dropped downstream like 'abc' above - not as a decision
    # about out-of-range numbers, but because the old
    # `_gridfilter_numeric_string?` answered false for BOTH "not shaped like a
    # number" and "too big", so they landed in the same bucket. Splitting the
    # two checks separates them, and out of range now raises the same way the
    # scalar coercion already raised for this exact value.
    #
    # Raising is the right side of that split: 'abc' carries no filter intent
    # to honour, so leaving it out is a narrower answer. A 20-digit number is
    # a well-formed value this database cannot represent - dropping it answers
    # with the other elements' rows and gives no hint that half the filter was
    # discarded, which is a wrong answer, not a narrow one.
    it 'raises GridfilterError for a too-large digit string element' do
      expect { User._gridfilter_number_coerce_set_element('9' * 30, field: :sign_in_count) }
        .to raise_error(ApplicationDocument::GridfilterError, /numeric filter value out of range/)
    end

    # The same value unquoted, which is what the issue is actually about: an
    # already-Numeric element returned here untouched, so it never reached any
    # check and took the request down in BSON serialization instead.
    it 'raises GridfilterError for a bare (unquoted) JSON number beyond int64' do
      expect { User._gridfilter_number_coerce_set_element(10**30, field: :sign_in_count) }
        .to raise_error(ApplicationDocument::GridfilterError, /numeric filter value out of range/)
    end

    # An in-range Numeric element still comes back as ITSELF, not as what the
    # coercion would have made of it - the coercion runs for its range check
    # only. A bare 5.5 against an Integer field stays 5.5 here, exactly as
    # before this change; narrowing that is a separate question from #2979.
    it 'passes an in-range Float element through unchanged, uncoerced' do
      expect(User._gridfilter_number_coerce_set_element(5.5, field: :sign_in_count)).to eq(5.5)
    end

    it 'passes an in-range Integer element through unchanged' do
      expect(User._gridfilter_number_coerce_set_element(5, field: :sign_in_count)).to eq(5)
    end
  end
end
