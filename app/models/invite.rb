# Custom implementation of a scoped invitation system
# since neither
#   https://github.com/scambra/devise_invitable (only good for creating users with a single invitiation at a time)
# nor
#   https://github.com/tomichj/invitation (not mongodb compatible)
# works for our requirements
class Invite < ApplicationDocument

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  field :email, type: String
  field :user_id, type: String
  field :invited_by_id, type: String
  field :invitable_id, type: String
  field :invitable_type, type: String
  field :actions, type: Hash
  field :app, type: String
  field :tenant_id, type: String
  field :token, type: String
  field :redirect_url, type: String
  field :accepted_at, type: DateTime
  field :auto_accept, type: Boolean, default: false
  field :done, type: Boolean, default: false
  field :valid_until, type: DateTime
  field :has_account, type: Boolean
  field :target_url, type: String

  # Samedis-care/samedis-care-issues#2810 review round 1: Mongoid's DateTime demongoize
  # silently turns an unparseable string into nil (Time.zone.parse returns nil, no raise),
  # indistinguishable by the time a validation runs from valid_until having been omitted
  # entirely - before_save's clamp_valid_until would then fill in the 30-day default and
  # the create would still return 200, exactly the silent-expiry-downgrade this issue was
  # about, just moved from "params stripped it" to "the value didn't parse". Capturing the
  # distinction requires hooking the setter, since that is the last point the raw value is
  # still available.
  def valid_until=(value)
    super
    @valid_until_unparseable = value.present? && valid_until.nil?
  end

  index({ email: 1 }, { sparse: true, unique: false, name: 'invite_emails' })
  index({ user_id: 1, email: 1, auto_accept: 1 }, { sparse: true, unique: false, name: 'invite_for_user' })
  index({ token: 1 }, { unique: false, name: 'invite_tokens' })
  index({ app: 1 }, { sparse: true, unique: false, name: 'invite_apps' })
  index({ tenant_id: 1 }, { sparse: true, unique: false, name: 'invite_tenants' })

  belongs_to :user, optional: true
  belongs_to :tenant, class_name: 'Actors::Tenant'

  before_save do |record|
    record.email = record.email.to_s.downcase
    record.valid_until = record.class.clamp_valid_until(record.valid_until)
  end

  before_validation do |record|
    record.user_id = record.get_user.id rescue nil if record.user_id.blank?
    record.token ||= record.token_generate
  end

  before_create do |record|
    record.has_account = User.email(record.email.to_s.downcase).present?
  end

  validates :invitable_type, :token, presence: true
  validates :invitable_id, presence: true, if: -> { %i(app).include?(self.invitable_type.to_sym) }
  validate :reject_unparseable_valid_until
  validate :reject_past_valid_until


  # max age of token
  def self.expire_time
    30.days.from_now
  end

  # Upper bound on a caller-supplied valid_until. Samedis-care/samedis-care-issues#2810:
  # Api::V1::App::Tenant::InvitationsController#params_create used to silently strip
  # `valid_until` via strong params, so every invite created through it (e.g.
  # samedis-care-backend's Staff auto-join flow, which sends 1.year.from_now) fell back
  # to the 30-day expire_time default no matter what the caller intended. Now that
  # `valid_until` is permitted, cap it server-side so a caller (buggy or malicious)
  # can't mint an effectively-permanent invite.
  MAX_VALID_UNTIL = 2.years

  # Applies the default expiry when none is supplied, and caps whatever IS supplied.
  # Idempotent: re-clamping an already-valid value on a later save (e.g. #accept!'s
  # update_attributes) is a no-op.
  def self.clamp_valid_until(value)
    candidate = value.presence || expire_time
    [candidate, MAX_VALID_UNTIL.from_now].min
  end

  def self.unclaimed
    available.where(user_id: nil)
  end

  def self.valid
    where(:valid_until.gt => Time.now)
  end

  def self.for_user(user)
    raise unless user.is_a?(User)
    any_of({ user_id: user.id }, { email: user.email })
  end

  def self.by_user(user)
    raise unless user.is_a?(User)
    where(invited_by_id: user.id)
  end

  def token_generate
    Digest::SHA1.hexdigest([SecureRandom.uuid, Time.now, rand].join)
  end

  def reject_unparseable_valid_until
    return unless @valid_until_unparseable

    errors.add(:valid_until, 'is not a valid date/time')
  end

  # Review round 2 on Samedis-care/samedis-care-issues#2810: the create-time upper bound
  # (MAX_VALID_UNTIL, above) had no matching lower bound, and permitting the attribute made
  # a past value reachable for the first time. A past valid_until produces an invite that is
  # simultaneously `persisted? == true` (200, looks fine) and `Invite.valid` == false forever
  # - which is also what both #accept! and MODEL_destroy (`Invite.valid`) key off, so it can
  # never be auto-accepted AND the DELETE endpoint can never remove it either (an empty
  # criteria still renders success). Reject outright rather than silently clamping forward
  # to Time.now: a caller who actually meant "already expired" would get a live invite
  # instead, which is its own silent-downgrade trap.
  def reject_past_valid_until
    return if valid_until.blank?
    return if valid_until >= Time.now

    errors.add(:valid_until, 'must not be in the past')
  end

  def is_valid?
    return false if self.done
    return false if (self.valid_until < Time.now)
    true
  end

  def app_actor
    @app_actor ||= Actors::App.available.named(app).first
  end

  def accept!(*args)
    return unless is_valid?

    action = "_process_accept_#{self.invitable_type}".to_sym
    raise "NO ACCEPT ACTION FOUND: #{action}" unless self.respond_to?(action)
    # only burn the invite once processing actually granted something, otherwise
    # it stays retryable on the next login instead of being accepted for nothing
    return false unless self.send(action, *args)

    self.update_attributes(accepted_at: Time.now, done: true)
  end

  def get_user
    return self.user if self.user.is_a?(User)
    User.where(email: self.email.to_s.downcase).first rescue nil
  end

  # processes this invite if invitable_type is 'tenant'
  def _process_accept_tenant(*_)
    tenant = Actor.tenants.find(tenant_id) rescue nil
    raise 'NO SUCH TENANT TO JOIN' unless tenant.is_a?(Actor)

    user = get_user
    raise 'NO SUCH USER' unless user.is_a?(User)

    # `available` matters: soft-deleting an ancestor cascades via a raw $set
    # (`Actor#before_save`), which neither trips the system protection guard nor renames
    # the group, so a group in a deleted subtree still matches name and system
    standard_group = tenant.descendants
                           .groups
                           .available
                           .where(system: true, name: :standard_user).first

    # A tenant without the system group `standard_user` is misconfigured - the group
    # comes from config/apps/samedis-care/actor_defaults/samedis-care.yml. Do not raise
    # here: this runs inside the login flow (User#check_acceptances) where an exception
    # would lock the user out of logging in entirely. Report it and leave the invite
    # unaccepted so the next login retries once the tenant is repaired.
    unless standard_group.is_a?(Actor)
      if standard_user_expected?(tenant)
        Sentry.capture_message(
          "Invite#accept!: no system group 'standard_user' below tenant - user not joined",
          level: :error,
          tags: { tenant_id: tenant_id.to_s },
          extra: { invite_id: id.to_s }
        )
        return false
      end

      # This app's tenants do not have that group, so there is nothing for this invite to
      # grant and nothing to report. Count it as processed - leaving it unaccepted would
      # re-run it on every login until it expires, for a condition that will never change.
      return true
    end

    # same reasoning: `map_into!` raises on a missing or unpersisted actor (User#actor is
    # optional) and can raise out of its own save!, and none of that may reach the login
    begin
      standard_group.map_into!(user.actor)
    rescue StandardError => e
      Sentry.capture_exception(
        e,
        tags: { tenant_id: tenant_id.to_s },
        extra: { invite_id: id.to_s, group_id: standard_group.id.to_s }
      )
      return false
    end

    true
  end

  # `standard_user` is a samedis-care actor default. invitable_type 'tenant' is settable for
  # any app's tenant (both invitation controllers permit it), and other apps declare other
  # groups - identity-management seeds `identity_management_admins` and no tenant_profiles
  # OU at all. So a missing group is only a misconfiguration where the tenant's own app
  # defaults ask for it.
  def standard_user_expected?(tenant)
    # Actors::Tenant#profiles_ou_defaults returns nil both when the app declares no
    # tenant_profiles OU and when the tenant has no organization node at all
    # (tenant.rb:100, and #organization filters by `available`, so a soft-deleted org tree
    # gives nil on a live tenant). Only the first is an answer about the app; treating the
    # second as "not expected" would burn the invite and report nothing, which is the
    # silent no-op this whole change exists to remove.
    return true if tenant.organization.nil?

    defaults = tenant.profiles_ou_defaults
    return false unless defaults.is_a?(Hash)

    Array(defaults['children']).any? { |child| child['name'].to_s.eql?('standard_user') }
  rescue StandardError
    # defaults unreadable: assume it was expected, so a real samedis-care misconfiguration
    # still gets reported instead of being swallowed
    true
  end

  def _process_accept_access_control(*_)
    user = get_user
    user.tenant_context = tenant_id

    if actions[:access_group_ids].is_a?(Array) || actions[:access_groups].is_a?(Array)
      _access_group_ids = actions[:access_group_ids] || []
      if actions[:access_groups].is_a?(Array)
        # dear rubocop, this is easier to read than an overly long one-liner
        _access_group_ids += tenant.group_ids_named(actions[:access_groups])
      end
      user.access_group_ids = _access_group_ids.compact.uniq
    end

    if actions[:add_access_group_ids].is_a?(Array) || actions[:add_access_groups].is_a?(Array)
      _add_ids = actions[:add_access_group_ids] || []
      if actions[:add_access_groups].is_a?(Array)
        # dear rubocop, this is easier to read than an overly long one-liner
        _add_ids += tenant.group_ids_named(actions[:add_access_groups])
      end
      user.add_access_group_ids(_add_ids.compact.uniq)
    end

    user.save! validate: false
    true
  end

end
