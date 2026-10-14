require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3296: page[limit]=0 is how a client
# asks for the count only. It reached Kaminari's per(0), i.e. Mongo limit(0), which Mongo reads
# as "no limit", so the whole collection came back and PAGE_LIMIT_MAX was bypassed. Like in
# samedis-care-backend, a limit of 0 now returns no records; the index response's total is
# counted separately and does not depend on paging.
RSpec.describe ApplicationDocument, '.paginate' do
  let(:model) { EmailBlacklist }
  let(:sfx) { SecureRandom.hex(4) }
  let(:domains) { Array.new(5) { |i| "paginate-#{sfx}-#{i}.test" } }

  before { domains.each { |domain| model.create!(domain: domain, active: true) } }

  after { model.where(:domain.in => domains).delete_all }

  def scope
    model.where(:domain.in => domains)
  end

  it 'returns no records for a limit of 0' do
    expect(scope.paginate(per_page: 0, page: 1).to_a).to eq([])
  end

  it 'treats a numeric string "0" the same way' do
    expect(scope.paginate(per_page: '0', page: 1).to_a).to eq([])
  end

  it 'still honours a positive limit' do
    expect(scope.paginate(per_page: 2, page: 1).to_a.size).to eq(2)
  end

  it 'still pages' do
    expect(scope.order_by(domain: 1).paginate(per_page: 2, page: 3).to_a.map(&:domain)).to eq([domains.last])
  end

  it 'still falls back to the default page size when no limit is given' do
    expect(scope.paginate(page: 1).to_a.size).to eq(5)
  end
end
