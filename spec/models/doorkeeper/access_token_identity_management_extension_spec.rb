require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/2422
# (Cognisys pentest: session token not destroyed on logout for MFA accounts)
#
# Api::V1::Doorkeeper::TokensController#revoke expires a token immediately via
# `_token.update_attributes(expires_in: -1)` for the "soft" (token_type_hint:
# 'access_token') logout branch. For an OTP-enabled user, this before_save callback
# unconditionally reset expires_in back to the full 30-day lifetime on every save --
# including that very same revoke -- so logout silently never took effect for MFA
# accounts. Non-MFA accounts were unaffected because the else branch never touches
# expires_in at all.
#
# A first fix only guarded the SAME save that set expires_in (checking
# expires_in_changed?), which missed a second, real trigger: the refresh_token grant
# flow (Api::V1::App::Doorkeeper::TokensController#create) finds a soft-revoked
# token by its still-live refresh_token, rotates that field, and calls save! on it --
# an unrelated save where expires_in_changed? is false, so that narrower guard would
# still revive the token. The fix (and the tests below) key off the token's current
# expires_in value instead, regardless of what this particular save changed.
RSpec.describe Doorkeeper::AccessToken do
  def build_user(otp:)
    user = User.new(
      email: "identity-management-extension-spec-#{SecureRandom.hex(4)}@test.local",
      first_name: 'Spec',
      last_name: 'Probe',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    )
    user.email_confirmation = user.email
    user.skip_confirmation!
    user.save!
    user.otp_enable! if otp
    user
  end

  let(:user) { build_user(otp: otp_enabled) }
  let!(:token) { described_class.create!(resource_owner_id: user.id) }

  after do
    token.delete
    user.delete
  end

  context 'when the user has MFA/OTP enabled' do
    let(:otp_enabled) { true }

    it 'persists an explicit soft-expiry (the logout/revoke path) instead of resetting it to the full lifetime' do
      token.update_attributes(expires_in: -1)
      token.reload

      expect(token.expires_in).to eq(-1)
    end

    it 'also protects an explicit expires_in of exactly 0' do
      token.update_attributes(expires_in: 0)
      token.reload

      expect(token.expires_in).to eq(0)
    end

    it 'still resets expires_in to the full lifetime when OTP is being confirmed (unrelated to logout)' do
      token.update_attributes(
        im_otp_provided: true, im_otp_tries: 0,
        expires_in: Doorkeeper.configuration.access_token_expires_in
      )
      token.reload

      expect(token.expires_in).to eq(Doorkeeper.configuration.access_token_expires_in)
      expect(token.im_otp_required).to be(true)
    end

    it 'still fully kills the token via revoke (the "hard" logout branch, unrelated to expires_in)' do
      token.revoke
      token.reload

      expect(token.revoked_at).to be_present
    end

    it 'stays dead across a later, unrelated save (mirrors the refresh_token grant rotating refresh_token)' do
      token.update_attributes(expires_in: -1)

      token.refresh_token = Doorkeeper::OAuth::Helpers::UniqueToken.generate
      token.save!
      token.reload

      expect(token.expires_in).to eq(-1)
    end

    it 'defaults a bare create (no explicit expires_in) to the full lifetime instead of leaving it nil' do
      # every real creation path passes expires_in explicitly, but nil must not be
      # mistaken for "deliberately killed" -- Doorkeeper::Expirable#expired? treats
      # nil as "never expires", which is more permissive than intended
      expect(token.expires_in).to eq(Doorkeeper.configuration.access_token_expires_in)
    end
  end

  context 'when the user does not have MFA/OTP enabled' do
    let(:otp_enabled) { false }

    it 'persists an explicit soft-expiry same as before this fix (never had this bug)' do
      token.update_attributes(expires_in: -1)
      token.reload

      expect(token.expires_in).to eq(-1)
      expect(token.im_otp_required).to be(false)
    end
  end
end
