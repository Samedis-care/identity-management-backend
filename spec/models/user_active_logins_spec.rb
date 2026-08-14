require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/2422
# (Cognisys pentest follow-up: a logged-out session still showed as active)
#
# User#active_logins / #expired_logins used to derive a token's expiry window from
# created_at plus the GLOBALLY configured access_token_expires_in, never looking at
# the token's own expires_in. Api::V1::Doorkeeper::TokensController#revoke kills a
# token for the "soft" logout branch (token_type_hint: 'access_token') by writing
# expires_in: -1 and deliberately leaving revoked_at nil, so a just-logged-out
# session still satisfied both conditions and kept counting as active for up to the
# full 30-day lifetime -- in exactly the screen a user opens to check that logout
# worked (Api::V1::User::AccountLoginsController), and it stayed out of the account
# activity log, which lists everything that is NOT an active login.
#
# These tests use a user WITHOUT OTP so IdentityManagementExtension's before_save
# leaves expires_in alone; the callback's own protection of an explicit expires_in
# for OTP users is covered by access_token_identity_management_extension_spec.rb.
RSpec.describe User do
  subject(:user) do
    _user = described_class.new(
      email: "user-active-logins-spec-#{SecureRandom.hex(4)}@test.local",
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

  # `created_at` is written with #set so it bypasses callbacks and timestamping --
  # the point of these fixtures is a token whose age and expires_in disagree.
  def create_token(expires_in:, age: nil, revoked: false)
    token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in:)
    token.set(created_at: age.ago) if age
    token.revoke if revoked
    token
  end

  let(:full_lifetime) { Doorkeeper.configuration.access_token_expires_in }

  # what logout writes: dead now, but revoked_at stays nil and the refresh_token survives
  let!(:soft_killed)  { create_token(expires_in: -1) }
  let!(:live)         { create_token(expires_in: full_lifetime) }
  let!(:aged_out)     { create_token(expires_in: full_lifetime, age: (full_lifetime + 1.day)) }
  let!(:never_expires) { create_token(expires_in: nil) }
  let!(:hard_revoked) { create_token(expires_in: full_lifetime, revoked: true) }

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    user.delete
  end

  describe '#active_logins' do
    it 'excludes a token soft-killed by logout, even though it was created just now' do
      expect(user.active_logins.pluck(:_id)).not_to include(soft_killed.id)
    end

    it 'includes a token whose own expiry window is still open' do
      expect(user.active_logins.pluck(:_id)).to include(live.id)
    end

    it 'excludes a token that aged past its own expires_in' do
      expect(user.active_logins.pluck(:_id)).not_to include(aged_out.id)
    end

    it 'includes a token with no expires_in (Doorkeeper treats nil as never expiring)' do
      expect(user.active_logins.pluck(:_id)).to include(never_expires.id)
    end

    it 'excludes a hard-revoked token' do
      expect(user.active_logins.pluck(:_id)).not_to include(hard_revoked.id)
    end
  end

  describe '#expired_logins' do
    it 'includes the token soft-killed by logout' do
      expect(user.expired_logins.pluck(:_id)).to include(soft_killed.id)
    end

    it 'includes a token that aged past its own expires_in' do
      expect(user.expired_logins.pluck(:_id)).to include(aged_out.id)
    end

    it 'excludes a token whose own expiry window is still open' do
      expect(user.expired_logins.pluck(:_id)).not_to include(live.id)
    end

    it 'excludes a token with no expires_in (never expires, so never expired)' do
      expect(user.expired_logins.pluck(:_id)).not_to include(never_expires.id)
    end

    it 'excludes a hard-revoked token (that is a revoked session, not an expired one)' do
      expect(user.expired_logins.pluck(:_id)).not_to include(hard_revoked.id)
    end
  end

  it 'partitions the unrevoked tokens between the two sets, with no overlap and none dropped' do
    active = user.active_logins.pluck(:_id)
    expired = user.expired_logins.pluck(:_id)
    unrevoked = Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil).pluck(:_id)

    expect(active & expired).to be_empty
    expect((active + expired).sort).to eq(unrevoked.sort)
  end
end
