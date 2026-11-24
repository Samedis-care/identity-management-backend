require 'rails_helper'

# Regression guard for the email-enumeration pentest findings (issues #2419, #2562).
#
# POST /api/v1/*app/recovery first returned a distinct 404 for a
# non-registered email (commit 72341e1 "be more specific"), and after that fix
# still split 400 "no recovery email configured" from 200 "mail sent". Both
# splits let an attacker learn whether an address is registered. The endpoint
# now answers every request with the same 200 and only sends the mail when a
# recovery email is configured.
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
  let(:user_without_recovery_email) { instance_double(User, is_a?: true, recovery_email: nil) }
  let(:user_with_recovery_email) { instance_double(User, is_a?: true, recovery_email: 'backup@example.com') }

  def stub_lookup(result, email: 'someone@example.com')
    where_result = double('where_result', first: result)
    allow(login_allowed_scope).to receive(:where).with(email: email).and_return(where_result)
  end

  def request_recovery(email = 'someone@example.com')
    post :create, params: { app: 'samedis-care', email: email }
    [response.status, JSON.parse(response.body)]
  end

  before do
    [user_without_recovery_email, user_with_recovery_email].each do |user|
      allow(user).to receive(:app_context=)
      allow(user).to receive(:send_recovery_instructions)
    end
  end

  it 'answers unregistered, no-recovery-email and recovery-email cases identically' do
    stub_lookup(nil)
    unregistered = request_recovery

    stub_lookup(user_without_recovery_email)
    without_recovery_email = request_recovery

    stub_lookup(user_with_recovery_email)
    with_recovery_email = request_recovery

    expect(unregistered).to eq(with_recovery_email)
    expect(without_recovery_email).to eq(with_recovery_email)

    status, body = with_recovery_email
    expect(status).to eq(200)
    expect(body.dig('meta', 'msg', 'success')).to be(true)
    expect(body.dig('meta', 'msg', 'message')).to eq(I18n.t('devise.mailer.recovery_instructions.started'))
  end

  it 'sends the recovery mail when a recovery email is configured' do
    stub_lookup(user_with_recovery_email)

    request_recovery

    expect(user_with_recovery_email).to have_received(:app_context=).with('samedis-care')
    expect(user_with_recovery_email).to have_received(:send_recovery_instructions)
  end

  it 'sends nothing when the user has no recovery email' do
    stub_lookup(user_without_recovery_email)

    request_recovery

    expect(user_without_recovery_email).not_to have_received(:send_recovery_instructions)
  end

  it 'treats a blank recovery email as not configured' do
    user = instance_double(User, is_a?: true, recovery_email: '')
    allow(user).to receive(:app_context=)
    allow(user).to receive(:send_recovery_instructions)
    stub_lookup(user)

    request_recovery

    expect(user).not_to have_received(:send_recovery_instructions)
  end

  it 'looks the user up by the normalized email' do
    stub_lookup(user_with_recovery_email)

    request_recovery('  SomeOne@Example.com ')

    expect(user_with_recovery_email).to have_received(:send_recovery_instructions)
  end

  it 'never passes a hash param into the user query' do
    allow(login_allowed_scope).to receive(:where).and_return(double('where_result', first: nil))

    post :create, params: { app: 'samedis-care', email: { '$ne' => 'x' } }

    expect(login_allowed_scope).to have_received(:where).with(email: kind_of(String))
    expect(response).to have_http_status(:ok)
  end
end
