class User < ApplicationDocument

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  include WithBlameNoIndex

  Shrine.plugin :mongoid
  include ImageUploader::Attachment.new(:image)

  MAX_TENANTS = 5000

  QUICKFILTER_COLUMNS = [:email, :first_name, :last_name]
  search_in *QUICKFILTER_COLUMNS

  strip_attributes collapse_spaces: true

  # enable active_model_otp
  include ActiveModel::OneTimePassword
  has_one_time_password one_time_backup_codes: true
  # virtual attributes that trigger the actual enable/disable after
  # the action is confirmed with an otp
  #attr_accessor :otp_enable, :otp_disable
  # custom override for more complex backup codes
  def otp_regenerate_backup_codes
    otp = ROTP::OTP.new(otp_column)
    backup_codes = Array.new(self.class.otp_backup_codes_count) do
      SecureRandom.hex[0...2].upcase + otp.generate_otp((SecureRandom.random_number(9e5) + 1e5).to_i).to_s
    end

    public_send("#{self.class.otp_backup_codes_column_name}=", backup_codes)
  end
  # helper methods, use only after the action is veriefied with a valid otp
  def otp_enable=(otp)
    return @otp_enable = nil if self.otp_enabled?
    self.otp_secret_key ||= User.otp_random_secret
    self.otp_backup_codes ||= self.otp_regenerate_backup_codes
    if otp.present? && self.authenticate_otp(otp)
      self.otp_enable!
      @otp_enable = nil
    else
      @otp_enable = otp
    end
  end
  def otp_enable
    @otp_enable
  end
  def otp_disable
    @otp_disable
  end
  def otp_disable=(otp)
    self.otp_disable! if otp.present? && self.otp_secret_key.present? && self.otp_enabled? && self.authenticate_otp(otp)
    @otp_disable = otp
  end

  def otp_enable!
    self.otp_secret_key ||= User.otp_random_secret
    unless self.otp_backup_codes.present? && self.otp_backup_codes.any?
      self.otp_regenerate_backup_codes
    end
    self.attributes = { otp_secret_key: self.otp_secret_key, otp_enabled: true, otp_backup_codes: self.otp_backup_codes }
    self.save validate: false
  end
  def otp_disable!
    self.attributes = { otp_secret_key: nil, otp_enabled: false, otp_backup_codes: nil }
    self.save validate: false
  end
  def get_provisioning_uri
    _app_context = self.app_context
    _app_context = 'identity-management' if _app_context.blank?
    provisioning_uri nil, issuer: _app_context
  end

  belongs_to :actor, class_name: 'Actors::User', inverse_of: :user, optional: true, autosave: true, dependent: :destroy
  belongs_to :supervisor_actor, :class_name => 'Actor', optional: true
  belongs_to :stand_in_actor, :class_name => 'Actor', optional: true
  has_many :account_activities,
    order: :created_at.desc,
    foreign_key: :user_id,
    class_name: AccountActivity, dependent: :delete_all

  field :email, type: String
  field :email_change, type: String
  field :active, type: Boolean, default: true
  field :deleted, type: Boolean, default: false
  field :pwd_reset_uid, type: String
  field :first_login_at, type: DateTime
  field :last_login_at, type: DateTime
  field :invalid_at, type: DateTime
  field :first_name, type: String
  field :last_name, type: String
  field :gender, type: Integer
  field :locale, type: String
  field :title, type: String
  field :short, type: String
  field :quickfilter, type: Array
  field :image_data, type: Hash # for shrine attachment
  field :mobile, type: String

  # { 123teant_id: [abc123, cfg1234], 456tenant: [tet12732] }
  field :tenant_access_group_ids, type: Hash
  field :tenants_cached, type: Array
  field :tenants_cached_at, type: Time
  field :tenant_candos_cached
  field :tenant_candos_cached_at, type: Time

  # Auth Fields
  field :encrypted_password, type: String, default: ""
  ## Recoverable
  field :reset_password_token, type: String
  field :reset_password_sent_at, type: Time
  ## Rememberable
  field :remember_created_at, type: Time
  ## Trackable
  field :sign_in_count, type: Integer, default: 0
  field :current_sign_in_at, type: Time
  field :last_sign_in_at, type: Time
  field :current_sign_in_ip, type: String
  field :last_sign_in_ip, type: String
  ## Confirmable
  field :confirmation_token, type: String
  field :confirmed_at, type: Time
  field :confirmation_sent_at, type: Time
  field :unconfirmed_email, type: String # Only if using reconfirmable
  # oauth
  field :provider, type: String
  field :uid, type: String
  field :token, type: String
  field :expires_at, type: Integer
  field :expires, type: Boolean
  field :refresh_token, type: String

  # otp / mfa
  field :otp_enabled, type: Boolean, default: false
  field :otp_secret_key, type: String
  field :otp_backup_codes, type: Array

  field :content_acceptance, type: Hash

  # protect critical records
  field :write_protected, type: Boolean, default: false
  field :system, type: Boolean, default: false

  index({ actor_id: 1, deleted: 1 }, { sparse: true, unique: true, name: 'user_actors' })
  index({ email: 1 }, { sparse: true, unique: true, name: 'user_emails' })
  index({ deleted: 1, active: 1, invalid_at: 1 }, { sparse: false })

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable

  devise :omniauthable, :omniauth_providers => [:facebook, :google_oauth2, :microsoft_graph, :twitter, :apple]

  # Set DoorKeeper for Devise
  devise :doorkeeper
  # include SentientUser

  # Validations
  validates :email, :first_name, :last_name, presence: true
  validates_confirmation_of :email, message: Proc.new { I18n.t("errors.email.confirmation") }, on: :create

  validates :email, format: {
    with: URI::MailTo::EMAIL_REGEXP,
    message: Proc.new { I18n.t('mongoid.errors.models.user.attributes.email.syntax') }
  }

  validates :email, uniqueness: {
    conditions: -> { all.available },
    message: Proc.new { I18n.t('mongoid.errors.models.user.attributes.email.uniqueness') },
    unless: Proc.new {|a| a.deleted? }
  }
  validates_confirmation_of :email, message: Proc.new { I18n.t("errors.email.confirmation") }, on: :create

  validates :password, presence: true,
            length: { in: 6..1024,
              message: Proc.new { I18n.t('mongoid.errors.models.user.attributes.password.too_short') },
            },
            confirmation: { case_sensitive: true }, on: :create
  validates :password_confirmation, :presence => true, :if => Proc.new{|u| u.password.present? }

  #Relations
  has_many :oauth_tokens, class_name: 'Doorkeeper::AccessToken', foreign_key: 'resource_owner_id', dependent: :destroy

  def self.gridfilter_fields
    %i(id actor_id locale email gender title first_name last_name created_at)
  end

  def self.email(address)
    where(email:address).first
  end

  def self.of_tenant_id(tenant_id)
    where(:actor_id.in => Actor.tenants.find(tenant_id).descendants.mappings.available.pluck(:map_actor_id))
  end

  def self.has_access_groups(group_ids=nil)
    # TODO: apply filter criteria here
  end

  def self.from_omniauth(auth)
    # Either create a User record or update it based on the provider (Google) and the UID   
    user = login_allowed.where(email: auth.info.email.downcase).first_or_initialize
    user.attributes = {
      provider: auth.provider,
      uid: auth.uid,
      token: auth.credentials.token,
      expires: auth.credentials.expires,
      expires_at: auth.credentials.expires_at,
      refresh_token: auth.credentials.refresh_token
    }
    user.locale ||= auth.info.locale
    user.first_name ||= (auth.info.first_name || auth.info.name  || auth.info.screen_name || auth.info.email)
    user.last_name ||= (auth.info.last_name || auth.info.name || auth.info.email)
    if user.encrypted_password.blank?
      _password = SecureRandom.uuid[0,18]
      user.password = _password
      user.password_confirmation = _password
      user.set_password = _password
    end
    user.confirmed_at ||= Time.now
    user.save!
    user
  end

  def name
    "#{first_name} #{last_name}"
  end

  before_save :image_derivatives, if: -> { image && image_changed? }
  def image_derivatives
    self.image_derivatives!
  end

  before_create do |user|
    if user.actor.nil?
      user.actor = Actors::User.create!(
        parent: Actor.user_container,
        name: user.email,
        user: user,
        short_name: user.get_short_name,
        full_name: user.get_full_name,
        title: user.get_short_name
      )
    end
  end

  after_create do |user|
    user.app_defaults!
  end

  before_save do |record|
    if record.write_protected && record.write_protected_was
      errors.add :write_protected, 'protection flag set'
      throw(:abort)
    end
    if record.system && record.deleted
      errors.add :system, 'protection flag set'
      throw(:abort)
    end
    if record.deleted_changed?
       # adds uuid after the email so the account can be re-created with same address
      record.email_uniquely_disabled! if record.deleted?
    end
    # persist changed access groups
    if record.access_group_ids_changed.is_a?(Array)
      record.send(:set_access_group_ids=, record.access_group_ids_changed)
      record.tenant_access_group_ids = record.determine_tenant_access_group_ids
      record.cache_expire!
    end
  end

  after_save do
    return if actor.nil?
    actor.set(
      deleted: deleted,
      active: active,
      short_name: get_short_name,
      full_name: get_full_name
    )
    ensure_app_membership!
  end

  before_destroy do |record|
    if record.system || record.write_protected
      errors.add :system, 'protection flag set'
      throw(:abort)
    end
  end

  def self.writable
    all.not.where(write_protected: true)
  end
  def self.deletable
    all.not.where(system: true)
  end

  def redirect_host=(_host)
    _host_uri = URI.parse(_host) rescue nil
    return nil unless _host_uri.is_a?(URI)
    _host_uri.path = ''
    _host_uri.query = ''
    _host_uri.fragment = nil
    _app_urls = Actors::App.pluck('config.url')
    _app_domains = _app_urls.collect do |u|
      _host = URI.parse(u).host.to_s rescue nil
      if _host.to_s.split('.').length > 2
        [_host, _host.split('.')[1..-1].join('.')]
      else
        [_host]
      end
    end.flatten.compact
    allowed_domain = begin
      _app_domains.include?(_host_uri.host.to_s) || (
        _host_uri.host.to_s.split('.').length > 2 &&
        _app_domains.include?(_host_uri.host.to_s.split('.')[1..-1].join('.'))
      )
    end
    allowed_host = [
      'localhost',
      '127.0.0.1'].include?(_host_uri.host) || IPAddr.new(_host_uri.host).private? rescue false
    @redirect_host = (allowed_domain||allowed_host) ? _host_uri.to_s.gsub('?', '') : nil
  end

  def redirect_host
    @redirect_host ||= nil
  end

  def redirect_path=(_path)
    @redirect_path = URI.parse(_path).request_uri rescue nil
  end

  def redirect_path
    @redirect_path ||= nil
    @redirect_path.to_s
  end

  def host
    return redirect_host if redirect_host.present?
    self.class.host(app_context)
  end

  def self.app_settings(app_context)
    @app_settings ||= {}
    @app_settings[app_context.to_slug.to_sym] ||= Actor.apps.named(app_context).first.settings rescue nil
  end

  def self.host(app_context='identity-management')
    Actors::App.named(app_context).first.try(:config).try(:url)
  end

  def self.per_app_settings
    @@auth_redirects ||= begin
      _apps = {}
      Actor.apps.available.each do |app|
        _apps[app.name.to_sym] = app.settings
      end
      _apps
    end
  end

  def mailer_defaults
    self.class.app_settings(self.app_context)[:mailer]
  end

  def self.redirect_urls(app_context)
    app_settings(app_context)[:redirects]
  end

  def redirect_urls
    raise "MISSING APP CONTEXT!" if self.app_context.blank?
    self.class.redirect_urls(self.app_context)
  end

  def self.redirect_url_login(app_context, invite_token: '')
    url_template(redirect_urls(app_context)[:login], { HOST: host(app_context), APP: app_context, INVITE_TOKEN: invite_token })
  end

  def redirect_url_acceptance(provided_values)
    self.class.url_template(self.redirect_urls[:acceptance], provided_values)
  end

  def redirect_url_authenticated(provided_values)
    self.class.url_template(self.redirect_urls[:authenticated], provided_values)
  end

  def redirect_url_confirm_account(provided_values)
    self.class.url_template(self.redirect_urls[:confirm_account], provided_values)
  end

  def redirect_url_reset_password(provided_values)
    self.class.url_template(self.redirect_urls[:reset_password], provided_values)
  end

  def self.url_template(url, provided_values)
    _needed_values = url.scan(/\%\{([^\}]*)\}/).map{|key|key<<''}.to_h
    url % _needed_values.symbolize_keys.merge(provided_values)
  end

  def self.cache_expire!
    criteria.set(
      tenant_candos_cached: nil,
      tenant_candos_cached_at: nil,
      tenants_cached: nil,
      tenants_cached_at: nil,
    )
  end

  def cache_expire
    @candos = nil
    @access_group_ids = nil
    @tenant_access_group_ids = nil
    @access_group_ids_changed = nil
    tenant_access_group_ids = nil
    tenants_cached = nil
    tenants_cached_at = nil
    tenant_candos_cached = nil
    tenant_candos_cached_at = nil
  end

  def cache_expire!
    cache_expire
    set(
      tenant_access_group_ids: nil,
      tenant_candos_cached: nil,
      tenant_candos_cached_at: nil,
      tenants_cached: nil,
      tenants_cached_at: nil
    )
  end

  def self.admin
    global_admin
  end

  def self.global_admin
    @@global_admin ||= where(email: 'admin@ident.services').first_or_create(
      system: true,
      actor: Actors::User.global_admin,
      first_name: 'Admin',
      last_name: 'Administrator',
      title: nil,
      gender: 0,
      confirmed_at: Time.now,
      set_password: ("#" * 18)
    )
  end

  # Filter by undeleted availabel users
  def self.available
    where(deleted: false)
  end

  def self.deleted
    where(deleted: true)
  end

  # Filter by users allowed to login
  def self.login_allowed
    available.where(active: true).not.where(:invalid_at.lt => Time.now)
  end

  def undelete!
    self.skip_reconfirmation!
    self.email = self.email.split('@')[0,2].join('@')
    self.confirm
    self.deleted = false
    self.save(validate:false)
  end

  def email_uniquely_disabled!
    self.skip_reconfirmation!
    self.email = "#{self.email.split('@')[0,2].join('@')}@#{self.id}.local"
    self.confirm
    self.email
  end

  def get_locale
    return :de if self.locale.blank?
    locale.downcase.underscore
  end

  # Controllers may set app-context at run time to filter candos
  # specific for the app
  def app_context=(app_name)
    @app_context_actor = nil
    @app_context = app_name.to_s.downcase
  end
  def app_context
    return 'identity-management' if @app_context.to_s.blank?
    "#{@app_context}".to_slug
  end
  def app_context_actor
    @app_context_actor ||= Actors::App.named(app_context).first
  end
  def tenant_context=(tenant_id)
    @tenant_context = tenant_id
  end
  def tenant_context
    #return tenants.pluck(:id).first if @tenant_context.blank?
    @tenant_context
  end
  def invite_token=(token)
    @invite_token = token
  end
  def invite_token
    @invite_token || ''
  end
  def tenant
    raise "MISSING TENANT CONTEXT" unless tenant_context.present?
    @tenant = nil unless @tenant.try(:id).to_s.eql?(tenant_context.to_s)
    @tenant ||= Actor.tenants.available.find(tenant_context)
  end

  def functionalities
    actor.functionalities
  end

  def app_defaults!
    return if self.app_context.nil?
    unless self.app_context.present?
      self.app_context = (self.oauth_tokens.order({ created_at: -1 }).first.im_app.to_slug rescue nil)
    end
    _app = Actors::App.named(self.app_context.to_s.to_slug).first
    if _app && _app.container_users
      _app.container_users.map_into!(self.actor, {}, cache_expire: false)
    end
  end

  # ensures the user's actor is mapped into app/*/users
  def ensure_app_membership!(_apps=nil)
    return unless actor.present?
    _apps = apps unless _apps.is_a?(Array)
    [_apps].flatten.each do |_app|
      _app.app_container_users.map_into!(actor, {}, cache_expire: false)
    end
  end

  # The actors of the apps the user is a member of
  def apps
    raise "MISSING ACTOR FOR: #{email}" if actor.nil?
    Actors::App.available.where(:id.in => actor.actor_ids)
  end

  # gets cached actors that are below the given actor id
  # @param {String} parental_id (e.g. a tenant actor id)
  # @return {Array} of Hashes with :id, :path, :parent_ids, :role_ids, :cando
  # unique by cando - so duplicate actor ids are very likely
  def actors_in_parent(parental_id)
    #@actors_in_parent ||= {}
    #@actors_in_parent[:parental_id] ||= 
    candos.select do |c|
      c.fetch(:parent_ids, []).collect(&:to_s).include?(parental_id.to_s)
    end
  end

  # gets cached actor ids that are below the given actor id
  # @param {String} parental_id (e.g. a tenant actor id)
  # @return {Array} of {String} ids
  def actors_ids_in_parent(parental_id)
    actors_in_parent(parental_id).pluck(:_id).collect(&:to_s).uniq.sort
  end

  # Helper that caches tenants of this user
  # Cache will be updated if there was a change in Actors (quite often) to be safe
  # or when ActorRoles have changed or cache is older than today.
  # @return {Array} of cando strings
  def tenants
    @tenants ||= if (self.tenants_cached.nil? || self.tenants_cached == [] ||
                     self.tenants_cached_at.nil? ||
                     self.tenants_cached_at < Time.now.beginning_of_day)
      _tenant_ids = Actors::Mapping.where(user_id: self.id).distinct(:tenant_id).compact
      _tenants = Actors::Tenant.available.where(:id.in => _tenant_ids).limit(MAX_TENANTS).tenant_collection(self)
      self.set(tenants_cached_at: Time.now, tenants_cached: _tenants)
      _tenants
    else
      tenants_cached
    end
  end

  # @TODO #826
  # Helper that caches candos per User
  # Cache will be updated if there was a change in Actors (quite often) to be safe
  # or when ActorRoles have changed or cache is older than today.
  # @return {Array} of cando strings
  def candos
    @candos ||= begin
      _cache_invalid = self.tenant_candos_cached.nil? || self.tenant_candos_cached_at.nil?
      unless _cache_invalid
        _cache_invalid = self.tenant_candos_cached_at < Time.now.beginning_of_day
      end
      if _cache_invalid
        @tenant_access_group_ids = nil
        @tenants = nil
        self.set(
          tenants_cached: nil,
          tenants_cached_at: nil,
          tenant_candos_cached_at: Time.now,
          tenant_candos_cached: get_tenant_candos
        )
      end
      tenant_candos_cached
    end
  end

  def get_tenant_candos
    self.tenant_access_group_ids = begin
      Actors::Mapping.where(user_id: self.id).get_tenant_candos.first.dig(:tenant_candos_cached) rescue []
    end
  end

  def update_tenant_candos!
    self.class.where(_id: _id).update_tenant_candos!
  end

  def self.get_tenant_candos
    Actors::Mapping.where(:user_id.in => criteria.pluck(:_id)).get_tenant_candos.pluck :tenant_candos_cached
  end

  def self.update_tenant_candos!
    Actors::Mapping.where(:user_id.in => criteria.pluck(:_id)).merge_tenant_candos!
  end

  def determine_tenant_access_group_ids
    self.tenant_access_group_ids = begin
      _access = Actors::Mapping.where(user_id: self.id).get_tenant_access_group_ids.first
      if _access.is_a?(Hash)
        _access.dig :tenant_access_group_ids
      else
        {}
      end
    end
  end

  # simple array of cando string regardless of tenants
  def global_candos(app_name=nil)
    @global_candos = self.candos.values.flatten.uniq.sort rescue []
    return @global_candos unless app_name.present?
    app_name = app_name.name if app_name.is_a?(Actors::App)
    @global_candos.select {|c| c.starts_with? app_name+'/' }
  end

  def cando_any?(of_these)
    return false unless of_these.is_a?(Array)
    return false if of_these.empty?
    # of_these is a multi-level array
    # first level is the action or action.format that would grant access
    # second level is an array of possible cando combinations
    # the first combo (can be single entry) matching will grant access

    of_these.each do |satisfying_actions|
      return false unless satisfying_actions.is_a?(Array)
      satisfying_actions.each do |cando_combo|
        return true if (self.global_candos & [cando_combo].flatten).length.eql?(cando_combo.length)
      end
    end
    false
  end

  # Indicate that this user will be invalidated
  def invalidate
    !self.invalid_at.blank?
  end

  def disable_devise_notifications!
    self.define_singleton_method(:send_devise_notification) { |*_| true }
  end

  # For setting the password (administative or after validation by password repeat)
  # @return {Bool} indication if password update was successful
  def set_password=(pwd)
    begin
      self.set(encrypted_password: password_digest(pwd))
      true
    rescue => e
      false
    end
  end

  def get_short_name
    "#{self.first_name} #{self.last_name}"
  end

  def get_full_name
    "#{self.last_name}, #{self.first_name}"
  end

  def image_b64=(b64_encoded)
    return if b64_encoded.blank?
    self.image = Base64StringIO.from_base64(b64_encoded)
  end

  def image=(file_data)
    return if file_data.blank?
    return super file_data unless file_data.is_a?(String)
    super Base64StringIO.from_base64(file_data)
  end

  def tenant_access_group_ids
    @tenant_access_group_ids ||= super
    unless (@tenant_access_group_ids.try(:keys).any? rescue false)
      @access_group_ids = nil
      @tenant_access_group_ids = tenant_access_group_ids = determine_tenant_access_group_ids
      self.save(validate: false) if self.changes.any?
    end
    @tenant_access_group_ids ||= {}
  end

  def access_group_ids_changed
    @access_group_ids_changed ||= nil
  end

  def access_group_ids
    raise "MISSING TENANT CONTEXT" unless tenant_context.present?
    #@access_group_ids ||= 
    tenant_access_group_ids[tenant_context]
  end

  def access_group_ids=(selected_ids)
    raise "MISSING TENANT CONTEXT" unless tenant_context.present?
    tenant_access_group_ids[tenant_context] = @access_group_ids_changed = @access_group_ids = selected_ids
    @access_group_ids
  end

  def add_access_group_ids(added_ids)
    raise "MISSING TENANT CONTEXT" unless tenant_context.present?
    return unless added_ids.is_a?(Array) && added_ids.any?
    tenant_access_group_ids[tenant_context] = @access_group_ids_changed = @access_group_ids = (access_group_ids.to_a+added_ids).compact.uniq
    @access_group_ids
  end

  # Convenience helper
  # @return {Bool} if user is male
  def male?
    self.gender.eql?(1)
  end

  # Convenience helper
  # @return {Bool} if user is female
  def female?
    self.gender.eql?(2)
  end

  def active_logins
    oauth_tokens.where(revoked_at: nil)
    .where(:created_at.gt => Doorkeeper.configuration.access_token_expires_in.seconds.ago)
  end
  def expired_logins
    oauth_tokens.where(revoked_at: nil)
    .where(:created_at.lte => Doorkeeper.configuration.access_token_expires_in.seconds.ago)
  end

  # this will personalize a formely anonymous token to the user
  # so #auto_accept_invites! can be run in the user context
  def claim_invite_token!(invite_token=nil)
    if invite_token.present?
      # if an invite token is supplied this will be personalized with the user_id
      invites = Invite.unclaimed.where(token: invite_token)
      return false unless invites.any?
      invites.set(user_id: self.id)
      return true
    end
    false
  end

  def auto_accept_invites!
    _invites = Invite.valid.where(auto_accept: true).for_user(self)
    return unless _invites.any?
    _invites.each do |invite|
      invite.accept!(current_user: self)
    end
    self.cache_expire!
  end

  def recent_invites
    Invite.where(user: self, :created_at.gte => 1.day.ago)
  end

  # Check if there are any content documents to accept (TOS)
  # Will accept outstanding auto-Invitations
  def check_acceptances(app=nil)
    context = app || app_context
    raise "MISSING APP CONTEXT" unless context.present?
    self.auto_accept_invites!
    @check_acceptances ||= begin
      current_acceptances = content_acceptance || {}
      current_acceptances[context] ||= {}
      required_acceptances = []
      Content.acceptance_required(context).each do |content, version|
        required_acceptances << content unless current_acceptances[context][content].eql?(version)
      end
      required_acceptances
    end
  end

  # Updates the version for accepted contents if the contents version
  # needs to be accepted
  # @param content {Content} to accept
  # @return {Boolean} indicating if the accept was persisted
  def accept_content!(content)
    is_required = acceptance_required?(content)
    if is_required
      current_acceptances = content_acceptance || {}
      current_acceptances[app_context] ||= {}
      current_acceptances[app_context][content.name] = content.version
      set(content_acceptance: current_acceptances)
      return true
    end
    false
  end

  def acceptance_required?(content)
    return false unless content.is_a?(Content)
    return false unless content.active?
    return false unless content.acceptance_required?
    current_acceptances = content_acceptance || {}
    current_acceptances[app_context] ||= {}
    if current_acceptances.try(app_context, content.name).to_i < content.version
      return true
    end
    false
  end

  # def email_required?
  #   false
  # end

  # def email_changed?
  #   false
  # end

  # use this instead of email_changed? for rails >= 5.1
  def will_save_change_to_email?
    false
  end

  def saved_change_to_encrypted_password?
    false
  end

  private
  def set_access_group_ids=(tenant_groups_selected)
    raise "MISSING TENANT CONTEXT" unless tenant_context.present?
    tenant_groups_available = Actors::Group.where(parent_ids: tenant.id)
    _resulting_ids = []
    if tenant_groups_selected.is_a?(Array)
      tenant_groups_available.each do |group|
        if tenant_groups_selected.include?(group.id.to_s)
          _resulting_ids << group.id.to_s if group.map_into!(self.actor, {}, cache_expire: false)
        else
          group.unmap_from!(self.actor, cache_expire: false)
        end
      end
      @access_group_ids = tenant_access_group_ids[tenant_context] = _resulting_ids
    end
  end

  def email_blacklisted
    unless EmailBlacklist.validate(self.email)
      errors.add(:email, I18n.t('errors.email.blacklisted'))
    end
  end

  def self.audience(recipients: {}, app_id: nil, preview: true)
    app = Actors::App.find(app_id)
    @audience = { tenant_count: 0, user_count: 0 }

    _user_ids = []
    _tenant_ids = []
    _group_ids = []
    _templated_group_ids = []
    _tenant_count = 0
    _has_actors = false

    # determine users via their actor mappings
    _determine_mappings = Actors::Mapping.available
    if recipients.fetch(:all_tenants, false)
      # all mappings below the app tenant container
      _has_actors = true
      _tenant_count = app.tenants.available.count
      _determine_mappings = _determine_mappings.where(:parent_ids => app.container_tenants.id)
    elsif recipients.fetch(:tenant_ids, []).any?
      # only mappings below specified tenant_ids
      _has_actors = true
      _tenant_ids = app.tenants.available.where(:_id.in => recipients[:tenant_ids]).only(:_id).pluck(:id)
      _tenant_count = _tenant_ids.count
      _determine_mappings = _determine_mappings.where(:parent_ids.in => _tenant_ids)
    else
      # tenant_ids is an empty array ensure no results are returned
      _has_actors = true
      _determine_mappings = _determine_mappings.none
    end
    if recipients.fetch(:all_groups, false)
      _has_actors = true
      _templated_group_ids = app.container_tenants.descendants.groups.only(:_id).pluck(:id)
      _determine_mappings = _determine_mappings.where(:parent_ids.in => _templated_group_ids)
    elsif recipients.fetch(:group_ids, []).any?
      _has_actors = true
      _group_ids = app.organization.descendants.groups.available.where(:_id.in => recipients[:group_ids]).only(:_id).pluck(:id)
      _templated_group_ids = app.container_tenants.descendants.groups.where(:template_actor_id.in => _group_ids).only(:_id).pluck(:id)
      _determine_mappings = _determine_mappings.where(:parent_ids.in => _templated_group_ids)
    else
      # group_ids is an empty array ensure no results are returned
      _has_actors = true
      _determine_mappings = _determine_mappings.none
    end

    _determine_users = User.available
    if _has_actors
      _determine_users = _determine_users.where(:actor_id.in => _determine_mappings.only(:map_actor_id).pluck(:map_actor_id))
    end
    if _has_actors && recipients.fetch(:user_ids, []).any?
      _determine_users = _determine_users.or(:_id.in => recipients[:user_ids])
    elsif recipients.fetch(:user_ids, []).any?
      _determine_users = _determine_users.where(:_id.in => recipients[:user_ids])
    end

    if _has_actors || recipients.fetch(:user_ids, []).any?
      unless preview
        _final_user_ids = _determine_users.only(:_id).pluck(:_id)
        @audience[:user_ids] = _final_user_ids
        @audience[:user_count] = _final_user_ids.count
      else
        @audience[:user_count] = _determine_users.count
      end
      @audience[:tenant_count] = _tenant_count
    end
    @audience
  end

end
