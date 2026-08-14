require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/2422
#
# Narrowing User#active_logins to the token's own expiry (so a logged-out session
# stops showing as active) must NOT also narrow what #destroy can reach. A token
# soft-killed by logout keeps a live refresh_token on purpose -- that is what powers
# the remembered-account fast path on the login page -- and deleting the record here
# is the only way to revoke that leftover credential from a DIFFERENT device. So
# MODEL (which #destroy resolves through) stays wider than MODEL_OVERVIEW (which
# #index resolves through).
#
# Follows the in-repo convention for controller scoping specs (see
# spec/controllers/api/v1/user/tenants_controller_spec.rb): instantiate the
# controller, stub current_user, and drive the real model_* resolvers.
RSpec.describe Api::V1::User::AccountLoginsController do
  subject(:controller_instance) { described_class.new }

  def build_user
    _user = User.new(
      email: "account-logins-controller-spec-#{SecureRandom.hex(4)}@test.local",
      first_name: 'Spec',
      last_name: 'Probe',
      password: 'Sup3rSecret!123',
      password_confirmation: 'Sup3rSecret!123'
    )
    _user.email_confirmation = _user.email
    _user.skip_confirmation!
    _user.save!
    _user
  end

  let(:user) { build_user }

  let(:full_lifetime) { Doorkeeper.configuration.access_token_expires_in }
  # what Api::V1::Doorkeeper::TokensController#revoke writes for the soft logout branch
  let!(:soft_killed) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: -1) }
  let!(:live) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime) }

  before do
    # The test env has no Devise secret configured, so the first lazy route load
    # (devise_for :users) would raise. Set one so the controller can be exercised.
    Devise.secret_key ||= 'test-suite-secret'

    without_partial_double_verification do
      allow(controller_instance).to receive(:current_user).and_return(user)
    end
  end

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    user.delete
  end

  describe 'the index scope (MODEL_OVERVIEW)' do
    it 'lists the live session' do
      expect(controller_instance.send(:model_index).pluck(:_id)).to include(live.id)
    end

    it 'does not list a session that was logged out' do
      expect(controller_instance.send(:model_index).pluck(:_id)).not_to include(soft_killed.id)
    end
  end

  describe 'the destroy scope (MODEL)' do
    it 'still resolves a logged-out session, so its surviving refresh_token stays revocable' do
      expect(controller_instance.send(:model_destroy).find(soft_killed.id.to_s)).to eq(soft_killed)
    end

    it 'still resolves a live session' do
      expect(controller_instance.send(:model_destroy).find(live.id.to_s)).to eq(live)
    end

    it 'stays scoped to the caller, so it never reaches another user\'s token' do
      other_user = build_user
      other = Doorkeeper::AccessToken.create!(resource_owner_id: other_user.id, expires_in: full_lifetime)

      expect { controller_instance.send(:model_destroy).find(other.id.to_s) }
        .to raise_error(Mongoid::Errors::DocumentNotFound)
    ensure
      other&.delete
      other_user&.delete
    end
  end
end
