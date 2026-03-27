require 'rails_helper'

RSpec.describe 'Social Auth Endpoint', type: :request do
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { 'test-key-id-123' }

  let(:jwks_json) do
    jwk = JWT::JWK.new(rsa_key, kid:)
    { 'keys' => [jwk.export] }.to_json
  end

  let(:valid_claims) do
    {
      'sub' => '123456789',
      'email' => "socialuser_#{SecureRandom.hex(4)}@example.com",
      'email_verified' => true,
      'name' => 'Social User',
      'given_name' => 'Social',
      'family_name' => 'User',
      'iss' => 'accounts.google.com',
      'aud' => 'test-google-client-id',
      'exp' => 1.hour.from_now.to_i,
      'iat' => Time.current.to_i
    }
  end

  def build_token(claims)
    JWT.encode(claims, rsa_key, 'RS256', { kid: })
  end

  before do
    # Stub JWKS HTTP fetch at the Net::HTTP level (works in request specs)
    jwks_body = jwks_json
    http_response = instance_double(Net::HTTPSuccess, body: jwks_body, is_a?: true)
    allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(Net::HTTP).to receive(:get_response).and_return(http_response)

    # Ensure cache doesn't interfere between examples
    Rails.cache.clear

    ENV['GOOGLE_OAUTH_CLIENT_ID'] = 'test-google-client-id'
    ENV['GOOGLE_IOS_CLIENT_ID'] = nil
    ENV['GOOGLE_ANDROID_CLIENT_ID'] = nil
  end

  describe 'POST /api/v1/:app/auth/social' do
    let(:url) { '/api/v1/identity-management/auth/social' }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    it 'returns 400 when provider is missing' do
      post url, params: { id_token: 'abc' }.to_json, headers: json_headers
      expect(response.status).to eq(400)
    end

    it 'returns 400 when id_token is missing' do
      post url, params: { provider: 'google' }.to_json, headers: json_headers
      expect(response.status).to eq(400)
    end

    it 'returns 401 for an unsupported provider' do
      post url, params: { provider: 'facebook', id_token: 'abc' }.to_json, headers: json_headers
      expect(response.status).to eq(401)
    end

    it 'returns 401 for a malformed token' do
      post url, params: { provider: 'google', id_token: 'not.a.valid.jwt' }.to_json, headers: json_headers
      expect(response.status).to eq(401)
    end

    context 'with a valid Google id_token' do
      let(:id_token) { build_token(valid_claims) }

      it 'creates a user and returns Doorkeeper tokens' do
        post url, params: { provider: 'google', id_token: }.to_json, headers: json_headers

        expect(response.status).to eq(200)
        body = JSON.parse(response.body)
        expect(body['access_token']).to be_present
        expect(body['refresh_token']).to be_present
        expect(body['token_type']).to eq('Bearer')
        expect(body['expires_in']).to be_present

        # User created with correct provider mapping
        user = User.where(email: valid_claims['email']).first
        expect(user).not_to be_nil
        expect(user.provider).to eq('google_oauth2')
        expect(user.uid).to eq('123456789')
      end

      it 'reuses an existing user with matching email' do
        email = valid_claims['email']
        User.create!(
          email:,
          password: 'TestPassword123!',
          password_confirmation: 'TestPassword123!',
          first_name: 'Existing',
          last_name: 'User',
          confirmed_at: Time.current
        )

        post url, params: { provider: 'google', id_token: }.to_json, headers: json_headers

        expect(response.status).to eq(200)
        expect(User.where(email:).count).to eq(1)
      end
    end

    context 'with a valid token but expired signature' do
      it 'returns 401' do
        expired_claims = valid_claims.merge('exp' => 1.hour.ago.to_i)
        id_token = build_token(expired_claims)
        post url, params: { provider: 'google', id_token: }.to_json, headers: json_headers
        expect(response.status).to eq(401)
        body = JSON.parse(response.body)
        expect(body.dig('meta', 'msg', 'message')).to include('expired')
      end
    end
  end
end
