require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3298: IdentityManagementExtension gave
# Doorkeeper::AccessToken a no-op `paginate`, so Api::V1::User::AccountLoginsController#index returned
# every unrevoked token of the user in one response and ignored page[limit], page[number], PAGE_LIMIT
# and PAGE_LIMIT_MAX (and the page[limit]=0 handling of #3296 never reached it).
RSpec.describe Doorkeeper::AccessToken, '.paginate' do
  let(:owner_id) { BSON::ObjectId.new }
  let(:lifetime) { Doorkeeper.configuration.access_token_expires_in }
  let!(:tokens) do
    # im_otp_required: false, so creating the token does not look the owner up (no user needed here)
    Array.new(5) do |i|
      described_class.create!(resource_owner_id: owner_id, expires_in: lifetime, im_otp_required: false, created_at: i.minutes.ago)
    end
  end

  after { described_class.where(resource_owner_id: owner_id).delete_all }

  def scope
    described_class.where(resource_owner_id: owner_id).order(created_at: -1)
  end

  it 'honours the limit' do
    expect(scope.paginate(per_page: 2, page: 1).to_a.size).to eq(2)
  end

  it 'pages: page 2 is not page 1' do
    first = scope.paginate(per_page: 2, page: 1).map(&:id)
    second = scope.paginate(per_page: 2, page: 2).map(&:id)

    expect(second).not_to eq(first)
    expect(second & first).to be_empty
    expect(first + second + scope.paginate(per_page: 2, page: 3).map(&:id)).to match_array(tokens.map(&:id))
  end

  it 'honours the padding' do
    expect(scope.paginate(per_page: 2, page: 1, padding: 3).map(&:id)).to eq(scope.to_a.last(2).map(&:id))
  end

  it 'returns no records for a limit of 0 (count only), like every other index' do
    expect(scope.paginate(per_page: 0, page: 1).to_a).to eq([])
  end

  it 'falls back to Kaminari\'s default page size when no limit is given, rather than returning everything' do
    expect(scope.paginate(page: 1).limit_value).to eq(Kaminari.config.default_per_page)
  end

  it 'shares the implementation with ApplicationDocument, so a fix there reaches both' do
    expect(described_class.singleton_class.ancestors).to include(Paginating)
    expect(ApplicationDocument.singleton_class.ancestors).to include(Paginating)
  end
end
