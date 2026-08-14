require 'rails_helper'

# Regression guard for the email-enumeration pentest finding (issue #2419).
#
# POST /api/v1/*app/recovery previously returned a distinct 404 for a
# non-registered email vs a 400/200 for a registered one (introduced by
# commit 72341e1 "be more specific"), letting an attacker enumerate valid
# accounts. The fix collapses "no such user" and "user exists but has no
# recovery email configured" into one identical 400 response.
RSpec.describe Api::V1::App::RecoveriesController, type: :controller do
  include Devise::Test::ControllerHelpers

  # The test env has no Devise secret configured, so the first lazy route load
  # (devise_for :users) would raise. Set one so the controller can be exercised.
  before do
    Devise.secret_key ||= 'test-suite-secret'
    @request.env['devise.mapping'] = Devise.mappings[:user]
    allow(User).to receive(:login_allowed).and_return(login_allowed_scope)
  end

  let(:login_allowed_scope) { double('login_allowed_scope') }

  def stub_lookup(result)
    where_result = double('where_result', first: result)
    allow(login_allowed_scope).to receive(:where).with(email: 'someone@example.com').and_return(where_result)
  end

  shared_examples 'a generic non-committal response' do
    it 'responds 400 with the recovery_email_unset message' do
      post :create, params: { app: 'samedis-care', email: 'someone@example.com' }

      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body.dig('meta', 'msg', 'error')).to eq('record_error')
      expect(body.dig('meta', 'msg', 'message')).to eq(I18n.t('errors.user.recovery_token.recovery_email_unset'))
    end
  end

  context 'when no user is registered for the email' do
    before { stub_lookup(nil) }

    include_examples 'a generic non-committal response'
  end

  context 'when the user exists but has no recovery email configured' do
    let(:recovery_user) { instance_double(User, is_a?: true, recovery_email: nil) }

    before { stub_lookup(recovery_user) }

    include_examples 'a generic non-committal response'
  end

  context 'when the user exists and has a recovery email configured' do
    let(:recovery_user) { instance_double(User, is_a?: true, recovery_email: 'backup@example.com') }

    before do
      stub_lookup(recovery_user)
      allow(recovery_user).to receive(:app_context=)
      allow(recovery_user).to receive(:send_recovery_instructions)
    end

    it 'starts the recovery process and responds 200' do
      post :create, params: { app: 'samedis-care', email: 'someone@example.com' }

      expect(recovery_user).to have_received(:send_recovery_instructions)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig('meta', 'msg', 'success')).to be(true)
    end
  end

  it 'never returns the removed not-found response for a non-existent user' do
    stub_lookup(nil)

    post :create, params: { app: 'samedis-care', email: 'someone@example.com' }

    expect(response).not_to have_http_status(:not_found)
  end
end
