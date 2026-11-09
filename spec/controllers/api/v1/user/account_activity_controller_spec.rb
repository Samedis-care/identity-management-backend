require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/3635
#
# The activity log is meant to leave out the entries of the user's currently active
# logins (those are listed by Api::V1::User::AccountLoginsController). The scope used
# to negate an equality against the whole id array (token_id $ne [id, ...]); a String
# field never equals an array, so every entry -- including the current session -- passed.
#
# Follows the in-repo convention for controller scoping specs (see
# spec/controllers/api/v1/user/account_logins_controller_spec.rb).
RSpec.describe Api::V1::User::AccountActivityController do
  subject(:controller_instance) { described_class.new }

  let(:user) do
    _user = User.new(
      email: "account-activity-controller-spec-#{SecureRandom.hex(4)}@test.local",
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

  let(:full_lifetime) { Doorkeeper.configuration.access_token_expires_in }
  let!(:live) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime) }
  let!(:other_live) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime) }
  # what logout writes: dead now, but revoked_at stays nil
  let!(:soft_killed) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: -1) }

  def activity_for(token, user_id: user.id)
    AccountActivity.create!(user_id: user_id, token_id: token.id.to_s, app: 'identity-management')
  end

  let!(:live_activity) { activity_for(live) }
  let!(:other_live_activity) { activity_for(other_live) }
  let!(:soft_killed_activity) { activity_for(soft_killed) }

  before do
    without_partial_double_verification do
      allow(controller_instance).to receive(:current_user).and_return(user)
    end
  end

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    AccountActivity.where(user_id: user.id).delete_all
    Actor.where(_id: user.actor_id).delete_all
    user.delete
  end

  describe 'the index scope (#model_index)' do
    subject(:ids) { controller_instance.send(:model_index).pluck(:_id) }

    it 'leaves out the entries of every currently active login' do
      expect(ids).not_to include(live_activity.id, other_live_activity.id)
    end

    it 'keeps the entry of a session that is no longer active' do
      expect(ids).to include(soft_killed_activity.id)
    end

    context 'when the user has no active login' do
      before { [live, other_live].each { |token| token.set(expires_in: -1) } }

      it 'lists every entry' do
        expect(ids).to contain_exactly(live_activity.id, other_live_activity.id, soft_killed_activity.id)
      end
    end
  end
end
