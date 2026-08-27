require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: ported 1:1 from samedis-care-backend's
# _gridfilter_text_to_criterion_value, with one addition on top of the port -
# `starts_with`'s collated-range id lookup is bounded (GRIDFILTER_STARTS_WITH_ID_LIMIT)
# and falls back to a plain regex once the match set exceeds it, per review feedback
# on PR #284: an unbounded prefix match on a large collection inlined every matching
# _id into the outer query and could exceed MongoDB's 16MB document size
# (Mongo::Error::MaxBSONSize, which isn't rescued as GridfilterError - an
# unhandled 500, not a slow page).
RSpec.describe ApplicationDocument, '._gridfilter_text_to_criterion_value' do
  let(:sfx) { SecureRandom.hex(4) }

  describe 'starts_with' do
    it 'matches via the collated-range id lookup when under the limit' do
      tenant = Actors::Tenant.create!(name: "startswith-#{sfx}-alpha")
      Actors::Tenant.create!(name: "startswith-#{sfx}-beta")

      result = Actors::Tenant._gridfilter_text_to_criterion_value('starts_with', "startswith-#{sfx}-al", field: :name)
      expect(result).to be_a(Mongoid::Criteria)
      expect(result.pluck(:_id)).to contain_exactly(tenant.id)
    end

    it 'falls back to a plain regex once the match set exceeds GRIDFILTER_STARTS_WITH_ID_LIMIT' do
      stub_const('ApplicationDocument::GRIDFILTER_STARTS_WITH_ID_LIMIT', 1)
      Actors::Tenant.create!(name: "startswith-#{sfx}-one")
      Actors::Tenant.create!(name: "startswith-#{sfx}-two")

      result = Actors::Tenant._gridfilter_text_to_criterion_value('starts_with', "startswith-#{sfx}", field: :name)
      expect(result).to be_a(Regexp)
      expect(Actors::Tenant.where(name: result).count).to eq(2)
    end
  end

  it 'contains is still a case-insensitive regex' do
    result = ApplicationDocument._gridfilter_text_to_criterion_value('contains', 'Foo')
    expect(result).to be_a(Regexp)
    expect(result.source).to eq('Foo')
    expect(result.options & Regexp::IGNORECASE).not_to eq(0)
  end
end
