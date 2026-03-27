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

    before do
      allow(provider).to receive(:redirect_uri).and_return('https://test.example.com/callback')
    end

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
  # OIDC Discovery
  # ──────────────────────────────────────────────
  describe '#discover!' do
    let(:discovery_doc) do
      {
        'authorization_endpoint' => 'https://sso.kunde.de/oauth2/v2.0/authorize',
        'token_endpoint' => 'https://sso.kunde.de/oauth2/v2.0/token',
        'userinfo_endpoint' => 'https://sso.kunde.de/oauth2/v2.0/userinfo',
        'jwks_uri' => 'https://sso.kunde.de/oauth2/v2.0/keys',
        'scopes_supported' => %w[openid profile email offline_access]
      }
    end

    before do
      allow(Rails.cache).to receive(:fetch).and_yield
    end

    context 'when issuer_url is set and discovery succeeds' do
      before do
        provider.issuer_url = 'https://sso.kunde.de/oauth2/v2.0'
        # Clear manually set values to test auto-population
        provider.write_attribute(:host, nil)
        provider.write_attribute(:authorize_url, nil)
        provider.write_attribute(:token_url, nil)
        provider.write_attribute(:userinfo_url, nil)
        provider.write_attribute(:scope, nil)
        allow(Faraday).to receive(:get).and_return(
          faraday_response(status: 200, body: discovery_doc)
        )
      end

      it 'populates host from authorization_endpoint' do
        provider.discover!
        expect(provider.host).to eq('sso.kunde.de')
      end

      it 'populates authorize_url path' do
        provider.discover!
        expect(provider.read_attribute(:authorize_url)).to eq('/oauth2/v2.0/authorize')
      end

      it 'populates token_url path' do
        provider.discover!
        expect(provider.read_attribute(:token_url)).to eq('/oauth2/v2.0/token')
      end

      it 'populates userinfo_url as full URL' do
        provider.discover!
        expect(provider.read_attribute(:userinfo_url)).to eq('https://sso.kunde.de/oauth2/v2.0/userinfo')
      end

      it 'populates jwks_uri' do
        provider.discover!
        expect(provider.jwks_uri).to eq('https://sso.kunde.de/oauth2/v2.0/keys')
      end

      it 'populates scope from supported scopes (openid profile email only)' do
        provider.discover!
        expect(provider.read_attribute(:scope)).to eq('openid profile email')
      end
    end

    context 'when fields are already manually set' do
      before do
        provider.issuer_url = 'https://sso.kunde.de/oauth2/v2.0'
        # host is already set to 'sso.example.com' from subject
        allow(Faraday).to receive(:get).and_return(
          faraday_response(status: 200, body: discovery_doc)
        )
      end

      it 'does not overwrite existing host' do
        provider.discover!
        expect(provider.host).to eq('sso.example.com')
      end
    end

    context 'when discovery endpoint returns non-200' do
      before do
        provider.issuer_url = 'https://broken.example.com'
        provider.write_attribute(:host, nil)
        allow(Faraday).to receive(:get).and_return(
          faraday_response(status: 404, body: { error: 'not_found' })
        )
      end

      it 'does not modify any fields' do
        provider.discover!
        expect(provider.host).to be_nil
      end
    end

    context 'when issuer_url is blank' do
      it 'does nothing' do
        provider.issuer_url = nil
        expect(Faraday).not_to receive(:get)
        provider.discover!
      end
    end
  end

  # ──────────────────────────────────────────────
  # OIDC Auto-Probe (host only)
  # ──────────────────────────────────────────────
  describe '#probe_and_discover!' do
    let(:discovery_doc) do
      {
        'issuer' => 'https://sso.example.com/oauth2/token',
        'authorization_endpoint' => 'https://sso.example.com/oauth2/authorize',
        'token_endpoint' => 'https://sso.example.com/oauth2/token',
        'userinfo_endpoint' => 'https://sso.example.com/oauth2/userinfo',
        'jwks_uri' => 'https://sso.example.com/oauth2/jwks',
        'scopes_supported' => %w[openid profile email]
      }
    end

    let(:faraday_conn) { instance_double(Faraday::Connection) }

    before do
      allow(Rails.cache).to receive(:fetch).and_yield
      allow(Faraday).to receive(:new).and_return(faraday_conn)
    end

    context 'when standard path fails but WSO2 path succeeds' do
      before do
        provider.issuer_url = nil
        provider.write_attribute(:authorize_url, nil)
        provider.write_attribute(:token_url, nil)
        provider.write_attribute(:userinfo_url, nil)

        call_count = 0
        allow(faraday_conn).to receive(:get) do |url|
          call_count += 1
          if url.include?('/oauth2/token/.well-known/')
            faraday_response(status: 200, body: discovery_doc)
          else
            faraday_response(status: 302, body: '')
          end
        end
        # discovery_config also fetches via Faraday.get (not the conn)
        allow(Faraday).to receive(:get).and_return(
          faraday_response(status: 200, body: discovery_doc)
        )
      end

      it 'sets issuer_url from the successful probe' do
        provider.probe_and_discover!
        expect(provider.issuer_url).to eq('https://sso.example.com/oauth2/token')
      end

      it 'populates endpoint URLs' do
        provider.probe_and_discover!
        expect(provider.read_attribute(:authorize_url)).to eq('/oauth2/authorize')
        expect(provider.jwks_uri).to eq('https://sso.example.com/oauth2/jwks')
      end
    end

    context 'when no discovery endpoint is found' do
      before do
        provider.issuer_url = nil
        allow(faraday_conn).to receive(:get).and_return(
          faraday_response(status: 302, body: '')
        )
      end

      it 'does not set issuer_url' do
        provider.probe_and_discover!
        expect(provider.issuer_url).to be_nil
      end
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
