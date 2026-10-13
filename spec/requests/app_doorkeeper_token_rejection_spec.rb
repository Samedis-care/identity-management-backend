require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2850.
#
# Api::V1::App::Doorkeeper::TokensController#create persists the token through
# `authorize_response` and promotes it to the full 30-day lifetime BEFORE it runs its
# rejection checks (unconfirmed user, unknown app, inactive user). Every rejected grant
# therefore used to leave a live token behind that User#active_logins listed as an
# active session for a device that never received any credential.
RSpec.describe 'POST /api/v1/:app/oauth/token rejections' do
  let(:password) { 'Sup3rSecret!123' }
  let(:user) do
    _user = User.new(
      email: "token-rejection-spec-#{SecureRandom.hex(4)}@test.local",
      first_name: 'Spec',
      last_name: 'Probe',
      password: password,
      password_confirmation: password
    )
    _user.email_confirmation = _user.email
    _user.skip_confirmation!
    _user.save!
    _user
  end

  def request_token(app: 'identity-management')
    post "/api/v1/#{app}/oauth/token",
         params: { grant_type: 'password', username: user.email, password: password, app: app }
  end

  # Devise.secret_key comes from ENV['DEVISE_SECRET_KEY'], which a plain local/CI test
  # run does not necessarily define; Devise raises on first token generation without it.
  before { allow(Devise).to receive(:secret_key).and_return('x' * 64) }

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    # user.destroy would be the natural teardown, but it only works once #2849 is merged.
    Actor.where(_id: user.actor_id).delete_all
    user.delete
  end

  context 'when the app is unknown' do
    before { request_token(app: 'no-such-app') }

    it 'answers with an error' do
      expect(response).to have_http_status(:bad_request)
    end

    it 'does not leave an active session behind' do
      expect(user.active_logins.count).to eq(0)
    end

    it 'keeps the rejected token revoked for the TTL sweep' do
      expect(Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil).count).to eq(0)
    end
  end

  context 'when the user is unconfirmed' do
    before do
      user.set(confirmed_at: nil)
      request_token
    end

    it 'answers with user_unverified' do
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not leave an active session behind' do
      expect(user.active_logins.count).to eq(0)
    end
  end

  context 'when a refresh grant belongs to a deactivated user' do
    before do
      token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: 3600, use_refresh_token: true)
      user.set(active: false)
      post '/api/v1/identity-management/oauth/token',
           params: { grant_type: 'refresh_token', refresh_token: token.refresh_token, app: 'identity-management' }
    end

    it 'answers 401 login_incorrect (not a record-not-found error)' do
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not leave a new active session behind (only the pre-existing token stays active)' do
      expect(user.active_logins.count).to eq(1)
    end
  end
end
