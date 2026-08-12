require 'rails_helper'

# Regression coverage for samedis-care-backend issue #2417. Actor#get_name's
# to_slug conversion does NOT neutralize literal HTML tags (verified: only
# incidentally strips quotes/slashes), and full_name gets zero transformation
# at all when explicitly set -- both are echoed back to samedis-care-backend's
# Tenant#handle field unvalidated (see that repo's PR #4126).
RSpec.describe Actors::Tenant do
  describe 'safe_html validation on :name / :short_name / :full_name' do
    it 'rejects the exact pentest payload in :name' do
      tenant = described_class.new(name: %(NewTestFacility"><s>sss<h1>TEST</h1>))
      tenant.valid?
      expect(tenant.errors[:name]).to be_present
    end

    it 'rejects HTML tags in :short_name' do
      tenant = described_class.new(short_name: '<h1>Injected</h1>')
      tenant.valid?
      expect(tenant.errors[:short_name]).to be_present
    end

    it 'rejects HTML tags in :full_name' do
      tenant = described_class.new(full_name: '<h1>Injected</h1>')
      tenant.valid?
      expect(tenant.errors[:full_name]).to be_present
    end

    it 'accepts an ordinary tenant name' do
      tenant = described_class.new(name: 'acme-gmbh')
      tenant.valid?
      expect(tenant.errors[:name]).to be_empty
    end
  end
end
