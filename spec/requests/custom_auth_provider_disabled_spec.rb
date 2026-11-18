require 'rails_helper'

# A CustomAuthProvider can be preconfigured with disabled: true before the
# customer's IdP is ready. Until it is enabled it must act as if it did not
# exist: users of its domains keep logging in with their password.
RSpec.describe 'Disabled CustomAuthProvider' do
  let(:sfx) { SecureRandom.hex(4) }

  # no host and no issuer_url, so saving triggers no OIDC discovery request; the
  # host for the authorize redirect is set afterwards, bypassing the callbacks
  let!(:provider) do
    CustomAuthProvider.create!(
      domain:, trusted_email_domains: [trusted_domain], client_id: 'samedis-client', client_secret: 'secret',
      disabled: true
    ).tap { |p| p.set(host: 'idp.example.com') }
  end

  let!(:im_app) { Actors::App.create!(name: app_name) }

  def app_name = "sso-disabled-app-#{sfx}"
  def domain = "sso-disabled-#{sfx}.example.com"
  def trusted_domain = "sso-disabled-mvz-#{sfx}.example.com"

  after do
    provider.delete
    im_app.delete
  end

  def auth_provider_hints
    get "/api/v1/app/info/#{app_name}"
    response.parsed_body.dig('data', 'attributes', 'auth_provider_hints')
  end

  it 'gives the frontend no SSO hint for its domains' do
    expect(auth_provider_hints).not_to include(Digest::MD5.hexdigest(trusted_domain))
  end

  it 'does not route the authorize request' do
    get "/api/v1/users/auth/#{trusted_domain}/#{app_name}"

    expect(response).to have_http_status(:not_found)
  end

  it 'does not route the callback' do
    get "/api/v1/users/auth/#{domain}/callback", params: { code: 'x', state: '{}' }

    expect(response).to have_http_status(:not_found)
  end

  context 'when enabled' do
    before { provider.update!(disabled: false) }

    it 'gives the frontend the SSO hint' do
      expect(auth_provider_hints).to include(Digest::MD5.hexdigest(trusted_domain))
    end

    it 'routes the authorize request to the IdP' do
      get "/api/v1/users/auth/#{trusted_domain}/#{app_name}"

      expect(response).to have_http_status(:redirect)
    end
  end
end
