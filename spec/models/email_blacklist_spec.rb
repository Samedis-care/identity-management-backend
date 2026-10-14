require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#3289: EmailBlacklist.validate is a
# case-sensitive exact match against addresses Devise has already downcased and stripped, so an
# entry saved as "Mailinator.COM" or " mailinator.com " never blocked anything.
RSpec.describe EmailBlacklist do
  let(:sfx) { SecureRandom.hex(4) }
  let(:domain) { "normalise-#{sfx}.test" }

  after { described_class.where(domain: domain).delete_all }

  describe 'saving an entry' do
    it 'downcases the domain' do
      entry = described_class.create!(domain: domain.upcase, active: true)

      expect(entry.reload.domain).to eq(domain)
    end

    it 'strips surrounding whitespace' do
      entry = described_class.create!(domain: "  #{domain} \n", active: true)

      expect(entry.reload.domain).to eq(domain)
    end

    it 'normalises on update too' do
      entry = described_class.create!(domain: domain, active: true)
      entry.update!(domain: "  #{domain.upcase}  ")

      expect(entry.reload.domain).to eq(domain)
    end

    it 'rejects a case variant of an existing domain as a duplicate' do
      described_class.create!(domain: domain, active: true)
      duplicate = described_class.new(domain: domain.upcase, active: true)

      expect(duplicate).not_to be_valid
    end
  end

  describe '.validate' do
    it 'blocks an address whose entry was saved with uppercase letters and whitespace' do
      described_class.create!(domain: " #{domain.upcase} ", active: true)

      expect(described_class.validate("someone@#{domain}")).to be(false)
    end

    it 'matches regardless of the case of the address passed in' do
      described_class.create!(domain: domain, active: true)

      expect(described_class.validate("Someone@#{domain.upcase}")).to be(false)
    end

    it 'lets an address through when the entry is inactive' do
      described_class.create!(domain: domain, active: false)

      expect(described_class.validate("someone@#{domain}")).to be(true)
    end

    it 'treats a blank address as blacklisted' do
      expect(described_class.validate(' ')).to be(false)
    end
  end

  describe '.import_list' do
    let(:file) { Tempfile.new(['blacklist', '.txt']) }

    before do
      file.write("# comment\n#{domain.upcase}\n  \n")
      file.flush
    end

    after { file.close! }

    it 'stores imported domains lowercase and does not duplicate them on re-import' do
      2.times { described_class.import_list(file.path) }

      expect(described_class.where(domain: domain).count).to eq(1)
      expect(described_class.where(domain: domain.upcase).count).to eq(0)
    end
  end
end
