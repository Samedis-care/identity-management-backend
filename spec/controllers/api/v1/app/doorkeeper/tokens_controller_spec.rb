require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2845: the refresh grant
# used to always rotate the previous token's refresh_token to a random value and
# leave revoked_at nil, regardless of whether that token's own access-token window
# had already closed. A token soft-killed by logout (or simply aged past its own
# expires_in) has nothing left to keep alive once its refresh_token is consumed, so
# rotating it just left an unrevoked, unusable oauth_access_tokens document behind
# forever -- nothing sweeps revoked_at: nil, only the 7-day TTL index on revoked_at
# itself (app/models/concerns/doorkeeper/access_token.rb). Every remembered-account
# login (grant_type=refresh_token after logout) added one more.
RSpec.describe Api::V1::App::Doorkeeper::TokensController do
  subject(:controller_instance) { described_class.new }

  def build_user
    _user = User.new(
      email: "tokens-controller-spec-#{SecureRandom.hex(4)}@test.local",
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

  let(:user) { build_user }
  let(:full_lifetime) { Doorkeeper.configuration.access_token_expires_in }

  before do
    # The test env has no Devise secret configured, so the first lazy route load
    # (devise_for :users) would raise. Set one so the controller can be exercised.
    Devise.secret_key ||= 'test-suite-secret'
  end

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    user.delete
  end

  describe '#invalidate_previous_token' do
    context 'when the previous token is still within its own expires_in' do
      let!(:live) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime) }
      let!(:original_refresh_token) { live.refresh_token }

      it 'rotates refresh_token to a value nobody holds' do
        controller_instance.send(:invalidate_previous_token, live)

        expect(live.reload.refresh_token).not_to eq(original_refresh_token)
      end

      it 'does not revoke it' do
        controller_instance.send(:invalidate_previous_token, live)

        expect(live.reload.revoked_at).to be_nil
      end
    end

    # what Api::V1::Doorkeeper::TokensController#revoke writes for the soft logout branch
    context 'when the previous token was soft-killed by logout' do
      let!(:soft_killed) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: -1) }

      it 'revokes it instead of leaving it unrevoked forever' do
        controller_instance.send(:invalidate_previous_token, soft_killed)

        expect(soft_killed.reload.revoked_at).not_to be_nil
      end
    end

    context 'when the previous token simply aged past its own expires_in' do
      let!(:aged_out) do
        token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime)
        token.set(created_at: (full_lifetime + 1.day).ago)
        token
      end

      it 'revokes it' do
        controller_instance.send(:invalidate_previous_token, aged_out)

        expect(aged_out.reload.revoked_at).not_to be_nil
      end
    end

    context 'when the previous token has no expires_in (Doorkeeper treats nil as never expiring)' do
      let!(:never_expires) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: nil) }
      let!(:original_refresh_token) { never_expires.refresh_token }

      it 'rotates refresh_token' do
        controller_instance.send(:invalidate_previous_token, never_expires)

        expect(never_expires.reload.refresh_token).not_to eq(original_refresh_token)
      end

      it 'does not revoke it' do
        controller_instance.send(:invalidate_previous_token, never_expires)

        expect(never_expires.reload.revoked_at).to be_nil
      end
    end
  end
end
