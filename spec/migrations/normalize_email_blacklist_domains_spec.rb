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

  it 'merges variants of one domain into a single row, keeping the already-normalised one' do
    keeper = insert(domain, active: false)
    insert(domain.upcase, active: true)
    run

    remaining = rows(domain, domain.upcase)
    expect(remaining.map { |row| row['_id'] }).to eq([keeper])
    expect(remaining.first['active']).to be(true)
  end

  it 'keeps the oldest row when no variant is normalised yet' do
    oldest = insert(domain.upcase)
    insert(" #{domain} ")
    run

    expect(rows(domain).map { |row| row['_id'] }).to eq([oldest])
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
