require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2845: the refresh grant
# used to always rotate the previous token's refresh_token to a random value and
# leave revoked_at nil, regardless of whether that token's own access-token window
# had already closed. A token soft-killed by logout (or simply aged past its own
# expires_in) has nothing left to keep alive once its refresh_token is consumed, so
# rotating it just left an unrevoked, unusable oauth_access_tokens document behind
# forever -- nothing sweeps revoked_at: nil, only the 7-day TTL index on revoked_at
# itself (app/models/concerns/doorkeeper/access_token.rb). Every remembered-account
# login (grant_type=refresh_token after logout) added one more.
RSpec.describe Api::V1::App::Doorkeeper::TokensController do
  subject(:controller_instance) { described_class.new }

  def build_user
    _user = User.new(
      email: "tokens-controller-spec-#{SecureRandom.hex(4)}@test.local",
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

  after do
    Doorkeeper::AccessToken.where(resource_owner_id: user.id).delete_all
    # user.delete skips dependent: :destroy, so the before_create-created Actors::User
    # would otherwise strand itself in the shared user_container (PR #293 review).
    # user.destroy is not the fix -- it raises SystemStackError on this model
    # (samedis-care-issues#2849, a mutual dependent: :destroy between User and
    # Actors::User) -- so delete the actor directly instead.
    Actor.where(_id: user.actor_id).delete_all
    user.delete
  end

  describe '#invalidate_previous_token' do
    context 'when the previous token is still within its own expires_in' do
      # use_refresh_token: true, so refresh_token is actually populated -- without it
      # Doorkeeper::AccessToken.create! stores refresh_token: nil, and asserting
      # "changed" against nil would pass for any write, proving nothing (PR #293 review).
      #
      # invalidate_previous_token always receives a document freshly loaded via
      # Doorkeeper::AccessToken.find_by (see #create), never the just-created
      # in-memory object -- that distinction matters because use_refresh_token? lives
      # on an in-memory ivar, never persisted: the just-created object still has it
      # set to true, which makes clearing refresh_token re-trigger the uniqueness
      # validation (validates_uniqueness_of :refresh_token, if: :use_refresh_token?)
      # against itself. A fresh find_by load has that ivar unset (false), matching
      # production. Reproduce that here instead of passing `live` directly.
      let!(:live) do
        Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime, use_refresh_token: true)
      end
      let(:fresh_live) { Doorkeeper::AccessToken.find_by(refresh_token: live.refresh_token) }

      it 'clears refresh_token so the consumed value can never be presented again' do
        controller_instance.send(:invalidate_previous_token, fresh_live)

        expect(live.reload.refresh_token).to be_nil
      end

      it 'does not revoke it' do
        controller_instance.send(:invalidate_previous_token, fresh_live)

        expect(live.reload.revoked_at).to be_nil
      end
    end

    # what Api::V1::Doorkeeper::TokensController#revoke writes for the soft logout branch
    context 'when the previous token was soft-killed by logout' do
      let!(:soft_killed) { Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: -1) }

      it 'revokes it instead of leaving it unrevoked forever' do
        controller_instance.send(:invalidate_previous_token, soft_killed)

        expect(soft_killed.reload.revoked_at).not_to be_nil
      end
    end

    context 'when the previous token simply aged past its own expires_in' do
      let!(:aged_out) do
        token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: full_lifetime)
        token.set(created_at: (full_lifetime + 1.day).ago)
        token
      end

      it 'revokes it' do
        controller_instance.send(:invalidate_previous_token, aged_out)

        expect(aged_out.reload.revoked_at).not_to be_nil
      end
    end

    context 'when the previous token has no expires_in (Doorkeeper treats nil as never expiring)' do
      # see the comment on fresh_live above -- same reason this needs a fresh reload
      let!(:never_expires) do
        Doorkeeper::AccessToken.create!(resource_owner_id: user.id, expires_in: nil, use_refresh_token: true)
      end
      let(:fresh_never_expires) { Doorkeeper::AccessToken.find_by(refresh_token: never_expires.refresh_token) }

      it 'clears refresh_token' do
        controller_instance.send(:invalidate_previous_token, fresh_never_expires)

        expect(never_expires.reload.refresh_token).to be_nil
      end

      it 'does not revoke it' do
        controller_instance.send(:invalidate_previous_token, fresh_never_expires)

        expect(never_expires.reload.revoked_at).to be_nil
      end
    end
  end
end
