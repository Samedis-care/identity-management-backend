require 'rails_helper'

RSpec.describe Api::V1::Devise::OmniauthCallbacksController, type: :controller do
  include Devise::Test::ControllerHelpers

  before { @request.env['devise.mapping'] = Devise.mappings[:user] }

  let(:provider_domain) { 'sso.example.com' }

  let(:provider) do
    instance_double(
      CustomAuthProvider,
      domain: provider_domain,
      create_code_verifier!: 'test-verifier-abc',
      # Return a plain string so redirect_to is happy
      passthru_uri: 'https://sso.example.com/oauth2/authorize?client_id=x',
      access_token: { 'access_token' => 'tok', 'expires_in' => 3600 },
      auth: double('omniauth_auth')
    )
  end

  before do
    # Avoid real DB lookups
    allow(CustomAuthProvider).to receive(:where).and_return(double(first: provider))
    allow(CustomAuthProvider).to receive(:find_by).and_return(provider)
    # failure path calls User.redirect_url_login
    allow(User).to receive(:redirect_url_login).and_return('https://app.example.com/login')
  end

  # ──────────────────────────────────────────────
  # dynamic_provider_authorize
  # ──────────────────────────────────────────────
  describe 'GET #dynamic_provider_authorize' do
    def do_request
      get :dynamic_provider_authorize,
          params: {
            provider: provider_domain,
            state: { app: 'test-app', redirect_host: 'https://app.example.com' }.to_json
          }
    end

    it 'stores a nonce in the session' do
      do_request
      expect(session[:oauth_state_nonce]).to be_present
    end

    it 'generates a different nonce on each request' do
      do_request
      nonce1 = session[:oauth_state_nonce]
      do_request
      nonce2 = session[:oauth_state_nonce]
      expect(nonce1).not_to eq(nonce2)
    end

    it 'embeds the nonce in the state passed to the provider' do
      captured_state = nil
      allow(provider).to receive(:passthru_uri) do |**kwargs|
        captured_state = JSON.parse(kwargs[:state]) rescue nil
        'https://sso.example.com/oauth2/authorize'
      end
      do_request
      expect(captured_state).not_to be_nil
      expect(captured_state['nonce']).to eq(session[:oauth_state_nonce])
    end

    it 'redirects to the provider authorize URI' do
      do_request
      expect(response).to be_redirect
      expect(response.location).to include('sso.example.com')
    end

    it 'sets the code_verifier cookie' do
      do_request
      expect(cookies[:code_verifier]).to eq('test-verifier-abc')
    end
  end

  # ──────────────────────────────────────────────
  # dynamic_provider_callback — CSRF nonce checks
  # ──────────────────────────────────────────────
  describe 'GET #dynamic_provider_callback' do
    let(:nonce) { 'secure-nonce-abc123' }
    let(:valid_state) do
      { app: 'test-app', redirect_host: 'https://app.example.com', nonce: }.to_json
    end
    let(:wrong_nonce_state) do
      { app: 'test-app', redirect_host: 'https://app.example.com', nonce: 'WRONG-NONCE' }.to_json
    end

    # Full oauth flow stubs for the "happy path" tests
    before do
      user_double = instance_double(
        User,
        id: BSON::ObjectId.new,
        errors: instance_double(ActiveModel::Errors, empty?: true),
        app_context: 'test-app',
        invite_token: nil,
        host: 'https://app.example.com',
        redirect_path: '/',
        'app_context=' => nil,
        'invite_token=' => nil,
        'redirect_path=' => nil,
        'redirect_host=' => nil,
        redirect_url_authenticated: 'https://app.example.com/?token=tok'
      )
      allow(user_double).to receive(:claim_invite_token!)
      allow(user_double).to receive(:auto_accept_invites!)
      allow(User).to receive(:from_omniauth).and_return(user_double)
      allow(Doorkeeper::AccessToken).to receive(:create).and_return(
        instance_double(
          Doorkeeper::AccessToken,
          token: 'tok', refresh_token: 'ref', expires_in: 3600
        )
      )
    end

    context 'when the nonce matches' do
      def do_valid_callback
        session[:oauth_state_nonce] = nonce
        get :dynamic_provider_callback,
            params: { provider: provider_domain, code: 'auth-code-xyz', state: valid_state }
      end

      it 'proceeds without raising a FailedAuthError' do
        expect { do_valid_callback }.not_to raise_error
      end

      it 'consumes the nonce from the session (one-time use)' do
        do_valid_callback
        expect(session[:oauth_state_nonce]).to be_nil
      end

      it 'redirects to the authenticated URL' do
        do_valid_callback
        expect(response).to be_redirect
        expect(response.location).to include('app.example.com')
      end
    end

    context 'when the nonce does not match' do
      def do_wrong_nonce_callback
        session[:oauth_state_nonce] = nonce
        get :dynamic_provider_callback,
            params: { provider: provider_domain, code: 'auth-code-xyz', state: wrong_nonce_state }
      end

      it 'redirects to the failure URL (oauth_error handler)' do
        do_wrong_nonce_callback
        expect(response).to be_redirect
      end

      it 'does not proceed to the oauth token flow' do
        expect(provider).not_to receive(:access_token)
        do_wrong_nonce_callback
      end
    end

    context 'when there is no nonce in the session' do
      it 'redirects to the failure URL (oauth_error handler)' do
        get :dynamic_provider_callback,
            params: { provider: provider_domain, code: 'auth-code-xyz', state: valid_state }
        expect(response).to be_redirect
      end
    end

    context 'when the state param is missing entirely' do
      it 'redirects to the failure URL (oauth_error handler)' do
        session[:oauth_state_nonce] = nonce
        get :dynamic_provider_callback,
            params: { provider: provider_domain, code: 'auth-code-xyz' }
        expect(response).to be_redirect
      end
    end
  end
end
