require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: dispatch-level coverage for the
# gridfilter engine ported 1:1 from samedis-care-backend - every filterType
# the rewritten `_gridfilter_condition_to_criterion` now understands, plus
# the filterType-aware empty/not_empty branching and the strict
# allowed_options validation (`_gridfilter_check_condition`).
RSpec.describe ApplicationDocument, '._gridfilter_condition_to_criterion' do
  let(:oid) { BSON::ObjectId.new }

  describe 'object_id filterType' do
    it 'equals resolves to the raw ObjectId under the field key' do
      condition = { filterType: 'object_id', type: 'equals', filter: oid.to_s }
      expect(User._gridfilter_condition_to_criterion(:actor_id, condition)).to eq(actor_id: oid)
    end

    it 'rejects an unsupported option for this filterType' do
      condition = { filterType: 'object_id', type: 'equals', filter: oid.to_s, dateFrom: '2026-01-01' }
      expect { User._gridfilter_condition_to_criterion(:actor_id, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /unsupported options/)
    end

    it 'raises GridfilterError for in_set with no filter array, rather than silently matching nothing' do
      condition = { filterType: 'object_id', type: 'in_set' }
      expect { User._gridfilter_condition_to_criterion(:actor_id, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /missing condition filter array/)
    end

    it 'raises GridfilterError for not_in_set with no filter array, rather than silently matching everything' do
      condition = { filterType: 'object_id', type: 'not_in_set' }
      expect { User._gridfilter_condition_to_criterion(:actor_id, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /missing condition filter array/)
    end

    it 'accepts a comma-joined String for in_set (the shape request batching produces)' do
      other_oid = BSON::ObjectId.new
      condition = { filterType: 'object_id', type: 'in_set', filter: "#{oid},#{other_oid}" }
      result = User._gridfilter_condition_to_criterion(:actor_id, condition)
      expect(result[:actor_id][:'$in']).to contain_exactly(oid, other_oid)
    end

    # Regression guard for review round 2 on PR #284: an Array-or-String shape check
    # alone still let an empty String/Array through - ensure_bson reduces "", "," and
    # [] all down to [], and an empty $nin is not "no match", it's "matches EVERY
    # document" for not_in_set - the exact silent-widening the round-1 fix was for,
    # just reached via an empty value instead of a missing one. Validate the RESULT
    # of ensure_bson, not just the input's shape.
    ['', ',', []].each do |empty_filter|
      it "raises GridfilterError for not_in_set with filter #{empty_filter.inspect} instead of matching everything" do
        condition = { filterType: 'object_id', type: 'not_in_set', filter: empty_filter }
        expect { User._gridfilter_condition_to_criterion(:actor_id, condition) }
          .to raise_error(ApplicationDocument::GridfilterError, /missing condition filter array/)
      end

      it "raises GridfilterError for in_set with filter #{empty_filter.inspect} instead of silently matching nothing" do
        condition = { filterType: 'object_id', type: 'in_set', filter: empty_filter }
        expect { User._gridfilter_condition_to_criterion(:actor_id, condition) }
          .to raise_error(ApplicationDocument::GridfilterError, /missing condition filter array/)
      end
    end
  end

  describe 'datetime filterType' do
    it 'equals resolves under the field key' do
      condition = { filterType: 'datetime', type: 'equals', dateTimeFrom: '2026-01-01T12:00:00Z' }
      result = User._gridfilter_condition_to_criterion(:created_at, condition)
      expect(result[:created_at]).to be_within(1).of(Time.parse('2026-01-01T12:00:00Z'))
    end

    it 'raises GridfilterError when dateTimeFrom is missing' do
      condition = { filterType: 'datetime', type: 'equals' }
      expect { User._gridfilter_condition_to_criterion(:created_at, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /missing condition dateTimeFrom/)
    end

    # Regression guard for review round 3 on PR #284: Time.zone.parse (needed to
    # satisfy Rails/TimeZone) returns nil rather than raising for input Date._parse
    # can't use at all ("yesterday", "hello") - unlike Time.parse, which raised.
    # Checking only the rescue silently let that nil flow into the built selector
    # instead of the intended GridfilterError - notEqual on garbage input matched
    # every row with the field set, instead of returning a 400.
    it 'raises GridfilterError for a dateTimeFrom that Time.zone.parse silently returns nil for' do
      condition = { filterType: 'datetime', type: 'not_equal', dateTimeFrom: 'yesterday' }
      expect { User._gridfilter_condition_to_criterion(:created_at, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /invalid dateTimeFrom/)
    end

    it 'raises GridfilterError for a dateTimeTo that Time.zone.parse silently returns nil for' do
      from = '2026-01-01T00:00:00Z'
      condition = { filterType: 'datetime', type: 'in_range', dateTimeFrom: from, dateTimeTo: 'yesterday' }
      expect { User._gridfilter_condition_to_criterion(:created_at, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /invalid dateTimeTo/)
    end

    it 'not_equal builds a $ne selector, not $not-on-scalar' do
      condition = { filterType: 'datetime', type: 'not_equal', dateTimeFrom: '2024-01-01T00:00:00Z' }
      result = User._gridfilter_condition_to_criterion(:created_at, condition)
      expect(result[:created_at].keys).to eq(['$ne'])
    end

    it 'not_equal executes as a real query, rather than a selector MongoDB itself rejects' do
      # regression guard for the actual defect: MongoDB rejects a bare scalar wrapped
      # in $not ("$not argument must be a regex or an object") - exercise the real
      # query, not just the built selector shape.
      condition = { filterType: 'datetime', type: 'not_equal', dateTimeFrom: '2024-01-01T00:00:00Z' }
      result = User._gridfilter_condition_to_criterion(:created_at, condition)
      expect { User.where(result).to_a }.not_to raise_error
    end

    it 'less_than_or_equal is supported (a real IM grid column - ProfileActivityModel#created_at - exposes it)' do
      condition = { filterType: 'datetime', type: 'less_than_or_equal', dateTimeFrom: '2026-01-01T00:00:00Z' }
      result = User._gridfilter_condition_to_criterion(:created_at, condition)
      expect(result).to eq(created_at: { '$lte' => Time.parse('2026-01-01T00:00:00Z') })
    end

    it 'greater_than_or_equal is supported (a real IM grid column - ProfileActivityModel#created_at - exposes it)' do
      condition = { filterType: 'datetime', type: 'greater_than_or_equal', dateTimeFrom: '2026-01-01T00:00:00Z' }
      result = User._gridfilter_condition_to_criterion(:created_at, condition)
      expect(result).to eq(created_at: { '$gte' => Time.parse('2026-01-01T00:00:00Z') })
    end
  end

  describe 'bool filterType' do
    it 'equals true on a default: true field folds nil/unset into the match' do
      condition = { filterType: 'bool', type: 'equals', filter: 'true' }
      expect(Actor._gridfilter_condition_to_criterion(:active, condition)).to eq(active: { '$in' => [true, nil] })
    end
  end

  describe 'empty / not_empty are filterType-aware' do
    it 'text empty matches nil-or-blank-string' do
      condition = { filterType: 'text', type: 'empty' }
      expect(User._gridfilter_condition_to_criterion(:email, condition)).to eq(email: { '$in' => [nil, ''] })
    end

    it 'object_id empty still matches nil only' do
      condition = { filterType: 'object_id', type: 'empty' }
      expect(User._gridfilter_condition_to_criterion(:actor_id, condition)).to eq(actor_id: { '$eq' => nil })
    end

    it 'not_empty on an unrecognized filterType falls back to a bare $ne nil' do
      condition = { filterType: 'bool', type: 'not_empty' }
      expect(User._gridfilter_condition_to_criterion(:email, condition)).to eq(email: { '$ne' => nil })
    end
  end

  describe 'text filterType hardening' do
    it 'matches anchors the regex on both ends' do
      condition = { filterType: 'text', type: 'matches', filter: 'foo' }
      result = User._gridfilter_condition_to_criterion(:email, condition)
      expect(result[:email].source).to eq('^foo$')
    end

    # Regression guard for review round 4 on PR #284: an empty filter: [] for
    # not_in_set built `$nin: []`, matching EVERY document instead of raising -
    # the same silent-widening already fixed for object_id, one filterType over.
    it 'raises GridfilterError for not_in_set with an empty filter array, rather than matching everything' do
      condition = { filterType: 'text', type: 'not_in_set', filter: [] }
      expect { User._gridfilter_condition_to_criterion(:email, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /missing condition filter array/)
    end
  end

  describe 'number filterType hardening' do
    # Same regression as the text case above, for the number filterType's
    # not_in_set branch.
    it 'raises GridfilterError for not_in_set with an empty filter array, rather than matching everything' do
      condition = { filterType: 'number', type: 'not_in_set', filter: [] }
      expect { Actor._gridfilter_condition_to_criterion(:children_count, condition) }
        .to raise_error(ApplicationDocument::GridfilterError, /missing condition filter array/)
    end
  end

  it 'raises GridfilterError for an unsupported filterType' do
    condition = { filterType: 'search', type: 'matches', filter: 'foo' }
    expect { User._gridfilter_condition_to_criterion(:email, condition) }
      .to raise_error(ApplicationDocument::GridfilterError, /unsupported condition filterType/)
  end
end
