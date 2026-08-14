require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2425 (pentest, Informational):
# only the frontend (identity-management-frontend's CreateAccount.tsx, zxcvbn score >= 2)
# rejected weak passwords — POST /register accepted them unchanged, e.g. "12345678". This
# adds the same zxcvbn-based check server-side, applied to every path that can set a
# password (not gated by `unless: :set_password` like the pre-existing length/confirmation
# validations — see the comment above `validate :validate_password_strength` in user.rb).
RSpec.describe User, '#validate_password_strength' do
  let(:sfx) { SecureRandom.hex(4) }
  let(:email) { "pw-strength-#{sfx}@password-strength-spec.test" }

  def build_user(password:, password_confirmation: password)
    described_class.new(
      email: email,
      email_confirmation: email,
      first_name: 'Weak',
      last_name: 'Password',
      password: password,
      password_confirmation: password_confirmation
    )
  end

  describe 'the exact PoC password from the pentest report' do
    it 'rejects "12345678" with a localized too_weak message' do
      user = build_user(password: '12345678')

      expect(user).not_to be_valid
      expect(user.errors[:password]).to include(I18n.t('mongoid.errors.models.user.attributes.password.too_weak'))
    end

    it 'never persists the weak password' do
      user = build_user(password: '12345678')
      expect(user.save).to be(false)
      expect(described_class.where(email: email).first).to be_nil
    end
  end

  describe 'other common weak passwords' do
    %w[password qwertyui adminadmin 11111111].each do |weak_password|
      it "rejects #{weak_password.inspect}" do
        user = build_user(password: weak_password)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include(I18n.t('mongoid.errors.models.user.attributes.password.too_weak'))
      end
    end
  end

  describe 'realistic passwords' do
    ['Tr0ub4dor&3xyz', 'correcthorsebatterystaple', 'Sup3rSecret!123'].each do |strong_password|
      it "accepts #{strong_password.inspect}" do
        user = build_user(password: strong_password)
        user.valid?
        expect(user.errors[:password]).to be_empty
      end
    end
  end

  describe 'minimum length (raised from 6 to 8 to match the frontend)' do
    it 'still rejects a 7-char password as too_short, independent of strength' do
      user = build_user(password: 'Ab3!xyz') # 7 chars, high character variety
      user.valid?
      expect(user.errors[:password]).to include(I18n.t('mongoid.errors.models.user.attributes.password.too_short'))
    end
  end

  describe User, '.password_strong_enough?' do
    it 'returns false for blank input' do
      expect(described_class.password_strong_enough?(nil)).to be(false)
      expect(described_class.password_strong_enough?('')).to be(false)
    end

    it 'does not raise for passwords beyond zxcvbn-ruby\'s max length (400 chars)' do
      expect(described_class.password_strong_enough?('a' * 400)).to be(true)
    end

    it 'accepts a SecureRandom.uuid-derived password (from_omniauth\'s auto-generated password)' do
      10.times do
        pwd = SecureRandom.uuid[0, 18]
        expect(described_class.password_strong_enough?(pwd)).to be(true)
      end
    end

    it 'is biased against the user\'s own email/name (mirrors CreateAccount.tsx userInputs)' do
      weak_but_long = 'JaneDoeJaneDoe' # long but built entirely from her own name
      strong = described_class.password_strong_enough?(weak_but_long, user_inputs: [])
      biased = described_class.password_strong_enough?(weak_but_long, user_inputs: %w[Jane Doe])
      expect(biased).to be(false) if strong # only assert the delta if the unbiased case wasn't already weak
    end
  end

  describe '#set_password= (admin / tenant-admin "set another user\'s password", and the ' \
           'unconfirmed-account re-registration path in User.new_with_session)' do
    let!(:user) do
      described_class.new(
        email: email,
        email_confirmation: email,
        first_name: 'Weak',
        last_name: 'Password',
        password: 'Sup3rSecret!123',
        password_confirmation: 'Sup3rSecret!123'
      ).tap do |u|
        u.skip_confirmation!
        u.save!
      end
    end

    after { user.delete }

    it 'does not persist the weak digest (skips the eager set() call) and reports the error on save' do
      original_digest = user.encrypted_password

      user.set_password = '12345678'
      expect(user.errors[:password]).to be_empty # set_password= itself never adds errors — see below

      reloaded = described_class.find(user.id)
      expect(reloaded.encrypted_password).to eq(original_digest), 'weak password must not reach the database'

      expect(user.save).to be(false)
      expect(user.errors[:password]).to include(I18n.t('mongoid.errors.models.user.attributes.password.too_weak'))
    end

    it 'does not persist a too-short-but-high-entropy password (score alone is not sufficient)' do
      original_digest = user.encrypted_password
      short_but_strong = 'Xk7mQaZ' # 7 chars, scores >= MIN_PASSWORD_STRENGTH_SCORE on its own

      expect(described_class.password_strong_enough?(short_but_strong)).to be(true)

      user.set_password = short_but_strong
      reloaded = described_class.find(user.id)
      expect(reloaded.encrypted_password).to eq(original_digest), 'too-short password must not reach the database'

      expect(user.save).to be(false)
      expect(user.errors[:password]).to include(I18n.t('mongoid.errors.models.user.attributes.password.too_short'))
    end

    it 'does not persist a too-long password (Zxcvbn::PasswordTooLong is rescued to true, length must still gate)' do
      original_digest = user.encrypted_password
      too_long = 'a' * 300 # exceeds both zxcvbn-ruby's 256-char limit and Devise's 128-char max

      user.set_password = too_long
      reloaded = described_class.find(user.id)
      expect(reloaded.encrypted_password).to eq(original_digest), 'too-long password must not reach the database'

      expect(user.save).to be(false)
      expect(user.errors[:password]).to be_present
    end

    it 'persists a strong password normally via set_password=' do
      user.set_password = 'Tr0ub4dor&3xyz'
      expect(user.valid_password?('Tr0ub4dor&3xyz')).to be(true)
    end
  end

  describe 'skip_password_strength_validation (internal bootstrap-only bypass)' do
    it 'is never a mass-assignable controller param on any User-facing controller' do
      permit_lists = [
        Api::V1::UsersController::PERMIT_CREATE,
        Api::V1::Apps::UsersController::PERMIT_UPDATE,
        Api::V1::Apps::Tenants::UsersController::PERMIT_UPDATE,
        Api::V1::Devise::RegistrationsController::PERMIT_CREATE
      ]
      permit_lists.each do |list|
        expect(list).not_to include(:skip_password_strength_validation)
      end
    end

    it 'bypasses the strength check when explicitly set (used only by User.global_admin)' do
      user = build_user(password: '12345678')
      user.skip_password_strength_validation = true
      user.valid?
      expect(user.errors[:password]).to be_empty
    end
  end
end
