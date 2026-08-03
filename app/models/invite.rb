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

  index({ email: 1 }, { sparse: true, unique: false, name: 'invite_emails' })
  index({ user_id: 1, email: 1, auto_accept: 1 }, { sparse: true, unique: false, name: 'invite_for_user' })
  index({ token: 1 }, { unique: false, name: 'invite_tokens' })
  index({ app: 1 }, { sparse: true, unique: false, name: 'invite_apps' })
  index({ tenant_id: 1 }, { sparse: true, unique: false, name: 'invite_tenants' })

  belongs_to :user, optional: true
  belongs_to :tenant, class_name: 'Actors::Tenant'

  before_save do |record|
    record.email = record.email.to_s.downcase
    record.valid_until ||= record.class.expire_time
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


  # max age of token
  def self.expire_time
    30.days.from_now
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
