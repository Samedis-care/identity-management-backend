require 'rails_helper'

RSpec.describe CustomAuthProvider, type: :model do
  subject(:provider) do
    described_class.new(
      domain: 'example.com',
      client_id: 'test-client-id',
      client_secret: 'test-client-secret',
      host: 'sso.example.com',
      trusted_email_domains: ['example.com', 'sub.example.com']
    )
  end

  # Minimal Faraday response double
  def faraday_response(status:, body:)
    instance_double(Faraday::Response, status:, body: body.to_json)
  end

  # ──────────────────────────────────────────────
  # access_token
  # ──────────────────────────────────────────────
  describe '#access_token' do
    let(:code) { 'auth-code-123' }
    let(:code_verifier) { 'verifier-abc' }
    let(:success_body) { { 'access_token' => 'tok', 'refresh_token' => 'ref', 'expires_in' => 3600 } }

    context 'when code_verifier is blank' do
      it 'raises FailedAuthError without making an HTTP request' do
        expect(Faraday).not_to receive(:post)
        expect { provider.access_token(code, code_verifier: '') }
          .to raise_error(CustomAuthProvider::FailedAuthError, /Missing code_verifier/)
      end
    end

    context 'when the token endpoint returns a non-200 status' do
      before do
        allow(Faraday).to receive(:post).and_return(
          faraday_response(status: 401, body: { error: 'invalid_client' })
        )
      end

      it 'raises FailedAuthError' do
        expect { provider.access_token(code, code_verifier:) }
          .to raise_error(CustomAuthProvider::FailedAuthError)
      end
    end

    context 'when the token endpoint returns invalid JSON' do
      before do
        allow(Faraday).to receive(:post).and_return(
          instance_double(Faraday::Response, status: 200, body: 'not-json}}}')
        )
      end

      it 'raises FailedAuthError (not a raw JSON::ParserError)' do
        expect { provider.access_token(code, code_verifier:) }
          .to raise_error(CustomAuthProvider::FailedAuthError)
      end
    end

    context 'when the token endpoint returns 200 with valid JSON' do
      before do
        allow(Faraday).to receive(:post).and_return(
          faraday_response(status: 200, body: success_body)
        )
      end

      it 'returns the parsed token hash' do
        result = provider.access_token(code, code_verifier:)
        expect(result['access_token']).to eq('tok')
        expect(result['expires_in']).to eq(3600)
      end
    end
  end

  # ──────────────────────────────────────────────
  # user_info
  # ──────────────────────────────────────────────
  describe '#user_info' do
    let(:access_token) { 'bearer-token-xyz' }
    let(:userinfo_body) { { 'sub' => 'u1', 'email' => 'alice@example.com', 'given_name' => 'Alice' } }

    context 'when the userinfo endpoint returns a non-200 status' do
      before do
        allow(Faraday).to receive(:get).and_return(
          faraday_response(status: 403, body: { error: 'forbidden' })
        )
      end

      it 'raises FailedAuthError' do
        expect { provider.user_info(access_token) }
          .to raise_error(CustomAuthProvider::FailedAuthError, /403/)
      end
    end

    context 'when the userinfo endpoint returns invalid JSON' do
      before do
        allow(Faraday).to receive(:get).and_return(
          instance_double(Faraday::Response, status: 200, body: '<<invalid>>')
        )
      end

      it 'raises FailedAuthError (not a raw JSON::ParserError)' do
        expect { provider.user_info(access_token) }
          .to raise_error(CustomAuthProvider::FailedAuthError)
      end
    end

    context 'when the userinfo endpoint returns 200 with valid JSON' do
      before do
        allow(Faraday).to receive(:get).and_return(
          faraday_response(status: 200, body: userinfo_body)
        )
      end

      it 'returns the parsed userinfo hash' do
        result = provider.user_info(access_token)
        expect(result['email']).to eq('alice@example.com')
      end
    end
  end

  # ──────────────────────────────────────────────
  # email_trusted?
  # ──────────────────────────────────────────────
  describe '#email_trusted?' do
    it 'accepts email on the primary domain' do
      expect(provider.email_trusted?('alice@example.com')).to be true
    end

    it 'accepts email on a trusted_email_domain' do
      expect(provider.email_trusted?('bob@sub.example.com')).to be true
    end

    it 'rejects email on an unknown domain' do
      expect(provider.email_trusted?('eve@attacker.com')).to be false
    end

    it 'rejects blank email' do
      expect(provider.email_trusted?('')).to be false
      expect(provider.email_trusted?(nil)).to be false
    end

    it 'rejects malformed email' do
      expect(provider.email_trusted?('not-an-email')).to be false
    end

    it 'is case-insensitive for domains' do
      expect(provider.email_trusted?('alice@EXAMPLE.COM')).to be true
    end
  end

  # ──────────────────────────────────────────────
  # PKCE helpers
  # ──────────────────────────────────────────────
  describe '#code_challenge' do
    it 'returns a valid S256 challenge for the verifier' do
      verifier = provider.create_code_verifier!
      expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier)).tr('=', '')
      expect(provider.code_challenge).to eq(expected)
    end

    it 'does not contain padding characters' do
      provider.create_code_verifier!
      expect(provider.code_challenge).not_to include('=')
    end
  end
end
