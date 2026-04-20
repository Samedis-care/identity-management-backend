require 'rails_helper'

RSpec.describe SocialTokenVerifier do
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { 'test-key-id-123' }

  let(:jwks_response) do
    jwk = JWT::JWK.new(rsa_key, kid:)
    { 'keys' => [jwk.export] }.to_json
  end

  before do
    # Stub JWKS fetching for all providers
    allow(Rails.cache).to receive(:fetch).and_call_original
    allow(Rails.cache).to receive(:fetch).with(/social_token_verifier:jwks/, anything) do |_key, _opts, &block|
      JSON.parse(jwks_response)
    end
  end

  def build_token(claims, key: rsa_key, algorithm: 'RS256', headers: { kid: })
    JWT.encode(claims, key, algorithm, headers)
  end

  describe 'unsupported provider' do
    it 'raises VerificationError' do
      expect {
        described_class.new(provider: 'facebook', id_token: 'whatever')
      }.to raise_error(SocialTokenVerifier::VerificationError, /Unsupported provider/)
    end
  end

  describe 'Google verification' do
    let(:provider) { 'google' }

    let(:valid_claims) do
      {
        'sub' => '123456789',
        'email' => 'user@example.com',
        'email_verified' => true,
        'name' => 'Test User',
        'given_name' => 'Test',
        'family_name' => 'User',
        'iss' => 'accounts.google.com',
        'aud' => 'test-google-client-id',
        'exp' => 1.hour.from_now.to_i,
        'iat' => Time.current.to_i
      }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GOOGLE_OAUTH_CLIENT_ID').and_return('test-google-client-id')
      allow(ENV).to receive(:[]).with('GOOGLE_IOS_CLIENT_ID').and_return('test-google-ios-id')
      allow(ENV).to receive(:[]).with('GOOGLE_ANDROID_CLIENT_ID').and_return(nil)
    end

    it 'verifies a valid Google id_token' do
      token = build_token(valid_claims)
      verifier = described_class.new(provider:, id_token: token)
      claims = verifier.verify!

      expect(claims['sub']).to eq('123456789')
      expect(claims['email']).to eq('user@example.com')
    end

    it 'accepts iOS client ID as audience' do
      token = build_token(valid_claims.merge('aud' => 'test-google-ios-id'))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.not_to raise_error
    end

    it 'rejects an invalid audience' do
      token = build_token(valid_claims.merge('aud' => 'wrong-client-id'))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /Invalid audience/)
    end

    it 'rejects an expired token' do
      token = build_token(valid_claims.merge('exp' => 1.hour.ago.to_i))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /expired/)
    end

    it 'rejects an invalid issuer' do
      token = build_token(valid_claims.merge('iss' => 'https://evil.com'))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /Invalid issuer/)
    end

    it 'rejects a token without email' do
      token = build_token(valid_claims.except('email'))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /No email/)
    end

    it 'rejects a token with unverified email' do
      token = build_token(valid_claims.merge('email_verified' => false))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /Email not verified/)
    end

    it 'rejects a token signed with a different key' do
      other_key = OpenSSL::PKey::RSA.generate(2048)
      token = build_token(valid_claims, key: other_key)
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /decode failed/)
    end

    it 'rejects a token with non-matching kid' do
      token = build_token(valid_claims, headers: { kid: 'unknown-kid' })
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(SocialTokenVerifier::VerificationError, /No matching key/)
    end
  end

  describe 'Apple verification' do
    let(:provider) { 'apple' }

    let(:valid_claims) do
      {
        'sub' => 'apple-user-001',
        'email' => 'user@icloud.com',
        'email_verified' => 'true',
        'iss' => 'https://appleid.apple.com',
        'aud' => 'care.samedis.app',
        'exp' => 1.hour.from_now.to_i,
        'iat' => Time.current.to_i
      }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('APPLE_CLIENT_ID').and_return('care.samedis.app')
      allow(ENV).to receive(:[]).with('APPLE_IOS_BUNDLE_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('APPLE_ANDROID_CLIENT_ID').and_return(nil)
    end

    it 'verifies a valid Apple id_token' do
      token = build_token(valid_claims)
      verifier = described_class.new(provider:, id_token: token)
      claims = verifier.verify!

      expect(claims['sub']).to eq('apple-user-001')
      expect(claims['email']).to eq('user@icloud.com')
    end

    it 'accepts email_verified as string "true"' do
      token = build_token(valid_claims)
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.not_to raise_error
    end
  end

  describe 'Microsoft verification' do
    let(:provider) { 'microsoft' }

    let(:valid_claims) do
      {
        'sub' => 'ms-user-001',
        'email' => 'user@company.com',
        'name' => 'Test User',
        'given_name' => 'Test',
        'family_name' => 'User',
        'iss' => 'https://login.microsoftonline.com/common/v2.0',
        'aud' => 'test-azure-client-id',
        'exp' => 1.hour.from_now.to_i,
        'iat' => Time.current.to_i
      }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AZURE_APPLICATION_CLIENT_ID').and_return('test-azure-client-id')
      allow(ENV).to receive(:[]).with('AZURE_IOS_CLIENT_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('AZURE_ANDROID_CLIENT_ID').and_return(nil)
    end

    it 'verifies a valid Microsoft id_token' do
      token = build_token(valid_claims)
      verifier = described_class.new(provider:, id_token: token)
      claims = verifier.verify!

      expect(claims['sub']).to eq('ms-user-001')
    end

    it 'accepts tenant-specific issuer via prefix match' do
      # Microsoft uses tenant-specific issuers
      token = build_token(valid_claims.merge('iss' => 'https://login.microsoftonline.com/consumers/v2.0'))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.not_to raise_error
    end

    it 'accepts tenant-uuid issuer for multi-tenant apps (common endpoint returns tenant-specific iss)' do
      # When the iOS app uses tenantId "common", Microsoft still returns tokens
      # with the real tenant UUID in the issuer, e.g. /d84b06ae-.../v2.0
      tenant_issuer = 'https://login.microsoftonline.com/d84b06ae-25e4-49ea-9898-6d015cb59f68/v2.0'
      token = build_token(valid_claims.merge('iss' => tenant_issuer))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.not_to raise_error
    end

    it 'rejects an issuer that looks like a tenant UUID but has an invalid format' do
      token = build_token(valid_claims.merge('iss' => 'https://login.microsoftonline.com/not-a-uuid/v2.0'))
      verifier = described_class.new(provider:, id_token: token)
      expect { verifier.verify! }.to raise_error(described_class::VerificationError, /Invalid issuer/)
    end
  end
end
