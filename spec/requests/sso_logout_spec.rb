require 'rails_helper'

# Samedis-care/samedis-care-issues#3666: logout used to revoke only the IM token, so
# the CustomAuthProvider's SSO session (Keycloak, Entra, ...) stayed alive and the
# next person on a shared device was signed in as the previous user. The revoke
# endpoint now hands back an OIDC RP-initiated logout URL for SSO sessions, and the
# IdP returns to a stable per-provider logged_out endpoint.
RSpec.describe 'SSO logout (RP-initiated)' do
  let(:password) { 'Sup3rSecret!123' }
  let(:sfx) { SecureRandom.hex(4) }
  let(:app_name) { "sso-logout-app-#{sfx}" }
  let(:domain) { "sso-logout-#{sfx}.example.com" }
  let(:end_session_url) { 'https://idp.example.com/realms/kh/protocol/openid-connect/logout' }

  let(:user) do
    _user = User.new(
      email: "sso-logout-spec-#{SecureRandom.hex(4)}@test.local",
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

  # no host and no issuer_url, so saving triggers no OIDC discovery request
  let!(:provider) do
    CustomAuthProvider.create!(
      domain:, trusted_email_domains: [domain],
      client_id: 'samedis-client', client_secret: 'secret', end_session_url:
    )
  end

  # the logged_out endpoint falls back to this app; production always has it
  # (Actors::App.ensure_im_app!), the test database not necessarily
  let!(:apps) do
    [app_name, 'identity-management'].filter_map do |name|
      Actors::App.create!(name:) unless Actors::App.named(name).exists?
    end
  end

  # User.per_app_settings and User.app_settings memoize per process
  def reset_app_settings_memo
    User.instance_variable_set(:@auth_redirects, nil)
    User.instance_variable_set(:@app_settings, nil)
  end

  before { reset_app_settings_memo }

  def create_token(**attrs)
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id, expires_in: 3600, use_refresh_token: true, scopes: 'api', im_app: app_name, **attrs
    )
  end

  def revoke(token, token_type_hint: nil)
    post '/api/v1/oauth/revoke', params: { access_token: token.token, token_type_hint: }.compact
  end

  def logout_url
    response.parsed_body.dig('meta', 'logout_url')
  end

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    AccountActivity.where(user_id: user.id).delete_all
    Actor.where(_id: user.actor_id).delete_all
    user.delete
    provider.delete
    apps.each(&:delete)
    reset_app_settings_memo
  end

  describe 'POST /api/v1/oauth/revoke' do
    context 'for a session from an SSO login' do
      let(:token) { create_token(im_sso_provider: domain) }

      # the samedis-care frontend logs out with this hint whenever it holds a refresh token
      it 'returns the IdP logout_url on the soft (access_token) branch' do
        revoke(token, token_type_hint: 'access_token')

        expect(response).to have_http_status(:ok)
        expect(logout_url).to start_with("#{end_session_url}?")
      end

      it 'returns the IdP logout_url on the full (refresh_token) branch' do
        revoke(token)

        expect(logout_url).to start_with("#{end_session_url}?")
      end

      it 'builds the logout_url from the provider config and the token app' do
        revoke(token)

        query = URI.decode_www_form(URI.parse(logout_url).query).to_h
        expect(query).to eq(
          'client_id' => 'samedis-client',
          'post_logout_redirect_uri' => provider.post_logout_redirect_uri,
          'state' => { app: app_name }.to_json
        )
      end

      it 'still revokes the token' do
        revoke(token)

        expect(token.reload.revoked_at).not_to be_nil
      end
    end

    context 'for a password session of the same user' do
      it 'returns no logout_url' do
        revoke(create_token)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['meta']).not_to have_key('logout_url')
      end
    end

    context 'when the provider has no end_session_url' do
      before { provider.set(end_session_url: nil) }

      it 'returns no logout_url' do
        revoke(create_token(im_sso_provider: domain))

        expect(response.parsed_body['meta']).not_to have_key('logout_url')
      end
    end

    context 'when the provider was deleted' do
      it 'returns no logout_url' do
        token = create_token(im_sso_provider: 'gone.example.com')
        revoke(token)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['meta']).not_to have_key('logout_url')
      end
    end
  end

  describe 'POST /api/v1/:app/oauth/token (refresh grant)' do
    # a bare Actors::App.create! has no container actors (those come from ensure_defaults!)
    before do
      allow_any_instance_of(Actors::App).to receive(:container_users).and_return(double(map_into!: true))
    end

    def refresh(token)
      post "/api/v1/#{app_name}/oauth/token",
           params: { grant_type: 'refresh_token', refresh_token: token.refresh_token, app: app_name }
    end

    def issued_token
      Doorkeeper::AccessToken.find_by(token: response.parsed_body['access_token'])
    end

    it 'carries the SSO provider over to the new token' do
      refresh(create_token(im_sso_provider: domain))

      expect(response).to have_http_status(:ok)
      expect(issued_token.im_sso_provider).to eq(domain)
    end

    it 'leaves a refreshed password session without SSO provider' do
      refresh(create_token)

      expect(response).to have_http_status(:ok)
      expect(issued_token.im_sso_provider).to be_nil
    end
  end

  describe 'GET /api/v1/users/auth/:provider/logged_out' do
    it 'redirects to the login page of the app named in state' do
      get "/api/v1/users/auth/#{domain}/logged_out", params: { state: { app: app_name }.to_json }

      expect(response).to redirect_to(User.redirect_url_login(app_name))
    end

    it 'falls back to the identity-management login page for an unknown app' do
      get "/api/v1/users/auth/#{domain}/logged_out", params: { state: { app: 'no-such-app' }.to_json }

      expect(response).to redirect_to(User.redirect_url_login('identity-management'))
    end

    it 'falls back to the identity-management login page without state' do
      get "/api/v1/users/auth/#{domain}/logged_out"

      expect(response).to redirect_to(User.redirect_url_login('identity-management'))
    end

    it 'does not redirect to a host taken from state' do
      get "/api/v1/users/auth/#{domain}/logged_out",
          params: { state: { app: app_name, redirect_host: 'https://evil.example.org' }.to_json }

      expect(response.location).not_to include('evil.example.org')
    end
  end
end
