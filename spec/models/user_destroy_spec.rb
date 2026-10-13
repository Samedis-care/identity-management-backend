require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/2849
#
# User#actor and Actor#user both declared `dependent: :destroy`, so User#destroy
# bounced between the two documents until SystemStackError. The cascade now lives
# on User#actor only.
RSpec.describe User do
  subject(:user) do
    _user = described_class.new(
      email: "user-destroy-spec-#{SecureRandom.hex(4)}@test.local",
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

  describe '#destroy' do
    let!(:actor_id) { user.actor_id }

    it 'does not recurse between User and Actors::User' do
      expect { user.destroy }.not_to raise_error
    end

    it 'removes the user document' do
      user.destroy
      expect(described_class.where(id: user.id)).to be_none
    end

    it 'removes the linked Actors::User document' do
      user.destroy
      expect(Actor.where(id: actor_id)).to be_none
    end
  end
end
