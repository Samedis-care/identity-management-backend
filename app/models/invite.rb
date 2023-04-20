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
    3.days.from_now # 72 hours
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
    self.send(action, *args)
    self.update_attributes(accepted_at: Time.now, done: true)
  end

  def get_user
    return self.user if self.user.is_a?(User)
    User.where(email: self.email.to_s.downcase).first rescue nil
  end

  # processes this invite if invitable_type is 'tenant'
  def _process_accept_tenant(*args)
    tenant = Actor.tenants.find(self.tenant_id) rescue nil
    raise "NO SUCH TENANT TO JOIN" unless tenant.is_a?(Actor)
    user = self.get_user
    raise "NO SUCH USER" unless user.is_a?(User)
    employee_group = tenant.descendants.groups.where(system: true, name: :staff_read_device_briefings).first
    raise "NO EMPLOYEE GROUP FOUND" unless employee_group.is_a?(Actor)
    employee_group.map_into!(user.actor)
    #puts "added #{user.name} to #{employee_group.path}"
    true
  end

  def _process_accept_access_control(*args)
    user = self.get_user
    user.tenant_context = tenant_id
    if actions[:access_group_ids].is_a?(Array)
      user.access_group_ids = actions[:access_group_ids]
    end
    if actions[:access_groups].is_a?(Array)
      user.access_group_ids = tenant.group_ids_named(actions[:access_groups])
    end
    if actions[:add_access_group_ids].is_a?(Array)
      user.add_access_group_ids(actions[:add_access_group_ids])
    end
    if actions[:add_access_groups].is_a?(Array)
      _add_ids = tenant.group_ids_named(actions[:add_access_groups])
      user.add_access_group_ids(_add_ids)
    end
    user.save! validate: false
    true
  end

end
