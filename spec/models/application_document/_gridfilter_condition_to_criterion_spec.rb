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

    it 'not_equal builds a Mongo-valid $ne selector, not an invalid $not-on-scalar' do
      condition = { filterType: 'datetime', type: 'not_equal', dateTimeFrom: '2024-01-01T00:00:00Z' }
      result = User._gridfilter_condition_to_criterion(:created_at, condition)
      expect(result[:created_at].keys).to eq(['$ne'])
      # regression guard for the actual defect: MongoDB rejects $not wrapping a bare
      # scalar ("$not argument must be a regex or an object") - exercise the real
      # query, not just the built selector shape.
      expect { User.where(result).to_a }.not_to raise_error
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
  end

  it 'raises GridfilterError for an unsupported filterType' do
    condition = { filterType: 'search', type: 'matches', filter: 'foo' }
    expect { User._gridfilter_condition_to_criterion(:email, condition) }
      .to raise_error(ApplicationDocument::GridfilterError, /unsupported condition filterType/)
  end
end
