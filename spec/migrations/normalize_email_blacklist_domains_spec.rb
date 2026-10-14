require 'rails_helper'
require Rails.root.join('db/migrate/20261014130000_normalize_email_blacklist_domains')

# Cover for the data fix of Samedis-care/samedis-care-issues#3289. Rows are written through the
# raw collection: the model now normalises on save, so it can no longer create the bad state.
RSpec.describe NormalizeEmailBlacklistDomains do
  let(:sfx) { SecureRandom.hex(4) }
  let(:domain) { "migrate-#{sfx}.test" }
  let(:other) { "migrate-other-#{sfx}.test" }

  def insert(name, active: true)
    id = BSON::ObjectId.new
    EmailBlacklist.collection.insert_one('_id' => id, 'domain' => name, 'active' => active)
    id
  end

  def rows(*names)
    EmailBlacklist.collection.find('domain' => { '$in' => names }).to_a
  end

  def run
    expect { described_class.up }.to output(/normalised/).to_stdout
  end

  after { EmailBlacklist.collection.delete_many('domain' => { '$in' => [domain, other, " #{domain.upcase} ", domain.upcase] }) }

  it 'downcases and strips an entry that only differs in form' do
    id = insert(" #{domain.upcase} ")
    run

    expect(EmailBlacklist.collection.find('_id' => id).first['domain']).to eq(domain)
  end

  it 'makes the entry block the lowercase address again' do
    insert(domain.upcase)
    expect(EmailBlacklist.validate("a@#{domain}")).to be(true)

    run

    expect(EmailBlacklist.validate("a@#{domain}")).to be(false)
  end

  it 'merges variants of one domain into the already-normalised row' do
    keeper = insert(domain, active: true)
    insert(domain.upcase, active: false)
    run

    expect(rows(domain, domain.upcase).map { |row| row['_id'] }).to eq([keeper])
  end

  it 'keeps the active flag of the normalised row, so a deactivated domain does not become a block' do
    insert(domain, active: false)
    insert(domain.upcase, active: true)
    run

    expect(rows(domain).first['active']).to be(false)
    expect(EmailBlacklist.validate("a@#{domain}")).to be(true)
  end

  it 'keeps the oldest row when no variant is normalised yet' do
    oldest = insert(domain.upcase)
    insert(" #{domain} ")
    run

    expect(rows(domain).map { |row| row['_id'] }).to eq([oldest])
  end

  it 'is active when any variant was and none is normalised yet' do
    insert(domain.upcase, active: false)
    insert(" #{domain} ", active: true)
    run

    expect(rows(domain).first['active']).to be(true)
  end

  it 'prints each merge with the resulting active flag' do
    insert(domain, active: false)
    insert(domain.upcase, active: true)

    expect { described_class.up }.to output(/merged 2 rows into #{Regexp.escape(domain)} \(active: false\)/).to_stdout
  end

  it 'leaves entries that are already normalised untouched' do
    id = insert(other, active: false)
    run

    expect(EmailBlacklist.collection.find('_id' => id).first).to include('domain' => other, 'active' => false)
  end

  it 'is idempotent' do
    insert(domain.upcase)
    run

    expect { described_class.up }.to output(/normalised 0 entries, merged away 0/).to_stdout
  end
end
