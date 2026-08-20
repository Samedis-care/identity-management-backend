require 'rails_helper'

# Regression guard for the repeat-request email-enumeration finding that
# re-opened issue #2419.
#
# POST /api/v1/*app/users/password answered identically for a registered and
# an unregistered address on the FIRST request, but a SECOND request within
# the 5-minute resend window returned a distinct 400 "reset_password_delayed"
# for a registered address while an unregistered one kept getting the generic
# 200 - the throttle branch itself was the oracle. The fix keeps the throttle
# (no duplicate mail sent) but always renders the same generic 200, on every
# branch: no such user, user found and mailed, user found and throttled.
RSpec.describe Api::V1::Devise::PasswordsController, type: :controller do
  include Devise::Test::ControllerHelpers

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

  def generic_response
    post :create, params: { app: 'samedis-care', user: { email: 'someone@example.com' } }
    JSON.parse(response.body)
  end

  shared_examples 'the generic recovery response' do
    it 'responds 200 with success and never a distinct error' do
      body = generic_response

      expect(response).to have_http_status(:ok)
      expect(body.dig('meta', 'msg', 'success')).to be(true)
      expect(body.dig('meta', 'msg', 'error')).to be_nil
    end
  end

  context 'when no user is registered for the email' do
    before { stub_lookup(nil) }

    include_examples 'the generic recovery response'
  end

  context 'when the user exists and is not within the resend window' do
    let(:user) { instance_double(User, present?: true, reset_password_sent_at: nil) }

    before do
      stub_lookup(user)
      allow(user).to receive(:app_context=)
      allow(user).to receive(:send_reset_password_instructions)
    end

    include_examples 'the generic recovery response'

    it 'sends the reset instructions' do
      generic_response

      expect(user).to have_received(:send_reset_password_instructions)
    end
  end

  context 'when the user exists and already has a reset pending within 5 minutes' do
    let(:user) { instance_double(User, present?: true, reset_password_sent_at: 1.minute.ago) }

    before do
      stub_lookup(user)
      allow(user).to receive(:send_reset_password_instructions)
    end

    include_examples 'the generic recovery response'

    it 'does not send a second reset mail' do
      generic_response

      expect(user).not_to have_received(:send_reset_password_instructions)
    end

    it 'never returns the removed reset_password_delayed error' do
      body = generic_response

      expect(response).not_to have_http_status(:bad_request)
      expect(body.dig('meta', 'msg', 'error')).not_to eq('reset_password_delayed')
    end
  end

  it 'renders byte-identical bodies for a throttled registered user and an unregistered one' do
    stub_lookup(nil)
    unregistered_body = generic_response

    throttled_user = instance_double(User, present?: true, reset_password_sent_at: 1.minute.ago)
    stub_lookup(throttled_user)
    throttled_body = generic_response

    expect(throttled_body).to eq(unregistered_body)
  end
end
