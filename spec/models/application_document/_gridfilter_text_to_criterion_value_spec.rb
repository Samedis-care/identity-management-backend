require 'rails_helper'

# Samedis-care/samedis-care-issues#2443: ported 1:1 from samedis-care-backend's
# _gridfilter_text_to_criterion_value, with one addition on top of the port -
# `starts_with`'s collated-range id lookup is bounded (GRIDFILTER_STARTS_WITH_ID_LIMIT),
# per review feedback on PR #284: an unbounded prefix match on a large collection
# inlined every matching _id into the outer query and could exceed MongoDB's 16MB
# document size (Mongo::Error::MaxBSONSize, which isn't rescued as GridfilterError -
# an unhandled 500, not a slow page).
#
# Above the limit this raises GridfilterError rather than falling back to a plain
# regex: the collated range is case- AND diacritic-insensitive (strength: 1), a bare
# Regexp::IGNORECASE is only case-insensitive, so a fallback would silently change
# which rows match once the count crosses the limit - a real bug on a German-language
# identity store, where an umlaut in name/last_name is the normal case, not an edge
# case (review round 2 on PR #284 caught this: "Müller" would stop matching once the
# match count crossed the bound).
RSpec.describe ApplicationDocument, '._gridfilter_text_to_criterion_value' do
  let(:sfx) { SecureRandom.hex(4) }

  describe 'starts_with' do
    it 'matches via the collated-range id lookup when under the limit' do
      tenant = Actors::Tenant.create!(name: "startswith-#{sfx}-alpha")
      Actors::Tenant.create!(name: "startswith-#{sfx}-beta")

      result = Actors::Tenant._gridfilter_text_to_criterion_value('starts_with', "startswith-#{sfx}-al", field: :name)
      # .pluck is Mongoid::Criteria-only - a wrong return type fails here with
      # NoMethodError before the id check ever gets a chance to matter
      expect(result.pluck(:_id)).to contain_exactly(tenant.id)
    end

    it 'is diacritic-insensitive, same as the collation it replaces a plain regex with' do
      tenant = Actors::Tenant.create!(name: "startswith-#{sfx}-müller")

      result = Actors::Tenant._gridfilter_text_to_criterion_value('starts_with', "startswith-#{sfx}-mu", field: :name)
      expect(result.pluck(:_id)).to contain_exactly(tenant.id)
    end

    it 'raises GridfilterError once the match set exceeds the limit, rather than silently changing match semantics' do
      stub_const('ApplicationDocument::GRIDFILTER_STARTS_WITH_ID_LIMIT', 1)
      Actors::Tenant.create!(name: "startswith-#{sfx}-one")
      Actors::Tenant.create!(name: "startswith-#{sfx}-two")

      expect { Actors::Tenant._gridfilter_text_to_criterion_value('starts_with', "startswith-#{sfx}", field: :name) }
        .to raise_error(ApplicationDocument::GridfilterError, /matches too many records/)
    end
  end

  it 'contains is still a case-insensitive regex' do
    result = described_class._gridfilter_text_to_criterion_value('contains', 'Foo')
    expect(result).to have_attributes(source: 'Foo', options: Regexp::IGNORECASE)
  end
end
