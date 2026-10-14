require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2572: User#email_blacklisted was
# defined but never registered as a validation, so a blacklisted domain registered normally.
RSpec.describe User, 'email blacklist' do
  let(:sfx) { SecureRandom.hex(4) }
  let(:domain) { "blacklist-spec-#{sfx}.test" }
  let(:email) { "someone-#{sfx}@#{domain}" }
  let(:password) { 'correct-horse-battery-staple-9' }
  let(:blocked_message) { I18n.t('errors.email.blacklisted') }

  def build_user(email:)
    described_class.new(
      email: email,
      email_confirmation: email,
      first_name: 'Black',
      last_name: 'List',
      password: password,
      password_confirmation: password
    )
  end

  after do
    EmailBlacklist.where(domain: domain).delete_all
    described_class.where(email: email).each(&:destroy)
  end

  context 'with an active entry for the domain' do
    before { EmailBlacklist.create!(domain: domain, active: true) }

    it 'rejects a new user on that domain' do
      user = build_user(email: email)

      expect(user).not_to be_valid
      expect(user.errors[:email]).to include(blocked_message)
    end

    it 'does not persist the user' do
      expect(build_user(email: email).save).to be(false)
      expect(described_class.where(email: email).first).to be_nil
    end
  end

  context 'with an inactive entry for the domain' do
    before { EmailBlacklist.create!(domain: domain, active: false) }

    it 'accepts a new user' do
      expect(build_user(email: email)).to be_valid
    end
  end

  context 'without an entry for the domain' do
    it 'accepts a new user' do
      expect(build_user(email: email)).to be_valid
    end
  end

  it 'adds no blacklist error on top of the presence error for a blank email' do
    user = build_user(email: '')

    expect(user).not_to be_valid
    expect(user.errors[:email]).not_to include(blocked_message)
  end

  it 'keeps an already registered user editable after their domain gets blacklisted' do
    user = build_user(email: email)
    user.skip_confirmation_notification!
    expect(user.save).to be(true)

    EmailBlacklist.create!(domain: domain, active: true)
    user.reload
    user.first_name = 'Renamed'

    expect(user).to be_valid
    expect(user.save).to be(true)
  end

  describe 'changing the address of an existing user' do
    let(:unlisted_email) { "keep-#{sfx}@blacklist-spec-unlisted-#{sfx}.test" }
    let(:user) do
      build_user(email: unlisted_email).tap do |record|
        record.skip_confirmation_notification!
        record.save!
      end
    end

    before do
      user
      EmailBlacklist.create!(domain: domain, active: true)
    end

    after { described_class.where(email: unlisted_email).each(&:destroy) }

    it 'is rejected when the new address is on a listed domain' do
      user.reload.email = email

      expect(user).not_to be_valid
      expect(user.errors[:email]).to include(blocked_message)
    end

    it 'is accepted when the new address is on an unlisted domain' do
      user.reload.email = "other-#{sfx}@blacklist-spec-unlisted-#{sfx}.test"

      expect(user).to be_valid
    end
  end

  describe '.from_omniauth' do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: 'google_oauth2', uid: sfx,
        info: { email: email, first_name: 'Sso', last_name: 'User' },
        credentials: { token: 't', expires: true, expires_at: 1.hour.from_now.to_i, refresh_token: 'r' }
      )
    end

    before { EmailBlacklist.create!(domain: domain, active: true) }

    it 'returns an unsaved user carrying the error instead of raising' do
      user = nil

      expect { user = described_class.from_omniauth(auth) }.not_to raise_error
      expect(user).not_to be_persisted
      expect(user.errors[:email]).to include(blocked_message)
    end
  end
end
