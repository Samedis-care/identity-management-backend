# this is replicating the logic from Devise::Models::Confirmable
# see https://github.com/heartcombo/devise/blob/main/lib/devise/models/confirmable.rb
# == Examples
#
#   User.find(1).recovery_confirm       # returns true unless it's already confirmed
#   User.find(1).recovery_confirmed?    # true/false
#   User.find(1).send_recovery_confirmation_instructions # manually send instructions
module Confirmable::RecoveryEmail
  extend ActiveSupport::Concern

  included do
    before_create :generate_recovery_confirmation_token, if: :recovery_confirmation_required?

    after_update :send_recovery_reconfirmation_instructions, if: :recovery_reconfirmation_required?
    before_update :postpone_recovery_email_change_until_confirmation_and_regenerate_confirmation_token, if: :postpone_recovery_email_change?

    ## manually make recovery_email Confirmable (not supported by devise)
    field :recovery_email, type: String
    field :recovery_confirmation_token, type: String
    field :recovery_confirmed_at, type: Time
    field :recovery_confirmation_sent_at, type: Time
    field :unconfirmed_recovery_email, type: String

    validates :recovery_email, format: {
      with: URI::MailTo::EMAIL_REGEXP,
      message: -> { I18n.t('mongoid.errors.models.user.attributes.email.syntax') }
    }, allow_blank: true
  end

  def initialize(*args, &block)
    @bypass_recovery_confirmation_postpone = false
    @skip_recovery_reconfirmation_in_callback = false
    @recovery_reconfirmation_required = false
    @skip_recovery_confirmation_notification = false
    @raw_recovery_confirmation_token = nil
    super
  end

  def self.required_fields(klass)
    required_methods = [:recovery_confirmation_token, :recovery_confirmed_at, :recovery_confirmation_sent_at]
    required_methods << :unconfirmed_recovery_email if klass.reconfirmable
    required_methods
  end

  def recovery_confirm
    return if unconfirmed_recovery_email.blank? || recovery_confirmed_at.is_a?(Time)

    if recovery_confirmation_period_expired?
      errors.add(:recovery_email, :recovery_confirmation_period_expired,
        period: Devise::TimeInflector.time_ago_in_words(self.class.confirm_within.ago))
      return false
    end

    self.recovery_confirmed_at = Time.now.utc
    self.recovery_email = unconfirmed_recovery_email
    self.unconfirmed_recovery_email = nil
    save(validate: false)
  end

  def recovery_confirmation_period_expired?
    self.class.confirm_within &&
      self.recovery_confirmation_sent_at &&
      (Time.now.utc > self.recovery_confirmation_sent_at.utc + self.class.confirm_within)
  end

  def redirect_url_confirm_recovery_email(provided_values)
    self.class.url_template(redirect_urls[:confirm_recovery_email], provided_values)
  end

  ###

  def pending_recovery_reconfirmation?
    self.class.reconfirmable && unconfirmed_recovery_email.present?
  end

  # Send confirmation instructions by email
  def send_recovery_confirmation_instructions
    unless @raw_recovery_confirmation_token
      generate_recovery_confirmation_token!
    end

    opts = pending_recovery_reconfirmation? ? { to: unconfirmed_recovery_email } : { }
    send_devise_notification(:recovery_confirmation_instructions, @raw_recovery_confirmation_token, opts)
  end

  def send_recovery_reconfirmation_instructions
    @recovery_reconfirmation_required = false

    unless @skip_recovery_confirmation_notification
      send_recovery_confirmation_instructions
    end
  end

  # Generates a new random token for confirmation, and stores
  # the time this token is being generated in confirmation_sent_at
  def generate_recovery_confirmation_token
    if recovery_confirmation_token && !recovery_confirmation_period_expired?
      @raw_recovery_confirmation_token = recovery_confirmation_token
    else
      self.recovery_confirmation_token = @raw_recovery_confirmation_token = Devise.friendly_token
      self.recovery_confirmation_sent_at = Time.now.utc
    end
  end

  def generate_confirmation_token!
    generate_recovery_confirmation_token && save(validate: false)
  end

  def postpone_recovery_email_change_until_confirmation_and_regenerate_confirmation_token
    @recovery_reconfirmation_required = true
    self.unconfirmed_recovery_email = recovery_email
    self.recovery_email = recovery_email_was
    self.recovery_confirmation_token = nil
    generate_recovery_confirmation_token
  end

  def postpone_recovery_email_change?
    postpone = self.class.reconfirmable &&
               will_save_change_to_recovery_email? &&
               !@bypass_confirmation_postpone &&
               recovery_email.present? &&
               (!@skip_recovery_reconfirmation_in_callback || !recovery_email_was.nil?)
    @bypass_recovery_confirmation_postpone = false
    postpone
  end

  def recovery_reconfirmation_required?
    self.class.reconfirmable &&
      @recovery_reconfirmation_required &&
      (recovery_email.present? || unconfirmed_recovery_email.present?)
  end

  module ClassMethods
    # Find a user by its confirmation token and try to confirm it.
    # If no user is found, returns a new user with an error.
    # If the user is already confirmed, create an error for the user
    # Options must have the confirmation_token
    def confirm_by_recovery_token(recovery_confirmation_token)
      # When the `confirmation_token` parameter is blank, if there are any users with a blank
      # `confirmation_token` in the database, the first one would be confirmed here.
      # The error is being manually added here to ensure no users are confirmed by mistake.
      # This was done in the model for convenience, since validation errors are automatically
      # displayed in the view.
      if recovery_confirmation_token.blank?
        confirmable = new
        confirmable.errors.add(:recovery_confirmation_token, :blank)
        return confirmable
      end

      confirmable = find_first_by_auth_conditions(recovery_confirmation_token: recovery_confirmation_token)
      confirmable.recovery_confirm if confirmable&.persisted?
      confirmable
    end
  end

end
