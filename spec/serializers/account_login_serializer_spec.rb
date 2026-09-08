require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2495: the account_logins
# #index endpoint now lists both active and soft-killed-but-unrevoked tokens (see
# Api::V1::User::AccountLoginsController), so a logged-out session whose refresh
# token still powers the remembered-account fast path is reachable for deletion
# from another device. Nothing that renders the list may present that entry as if
# it were an active session - the `active` attribute is what tells them apart.
RSpec.describe AccountLoginSerializer, type: :model do
  let(:full_lifetime) { Doorkeeper.configuration.access_token_expires_in }

  # a token needs a resource_owner_id it can resolve to a User -- IdentityManagementExtension's
  # before_save callback checks record.user.otp_enabled?, which raises on a nil user
  let!(:user) do
    _user = User.new(
      email: "account-login-serializer-spec-#{SecureRandom.hex(4)}@test.local",
      first_name: 'Spec',
      last_name: 'Probe',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    )
    _user.email_confirmation = _user.email
    _user.skip_confirmation!
    _user.save!
    _user
  end

  let!(:live) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime) }
  # what Api::V1::Doorkeeper::TokensController#revoke writes for the soft logout branch
  let!(:soft_killed) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: -1) }

  after do
    live.delete
    soft_killed.delete
    user.delete
  end

  it 'marks a live session as active' do
    attrs = described_class.new(live).serializable_hash[:data][:attributes]

    expect(attrs[:active]).to be true
  end

  it 'marks a logged-out session as not active, even though it is still listed and deletable' do
    attrs = described_class.new(soft_killed).serializable_hash[:data][:attributes]

    expect(attrs[:active]).to be false
  end
end
