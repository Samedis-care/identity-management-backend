# Add custom stuff to the Token class (oauth_access_tokens collection in mongodb)
# included to Doorkeeper::AccessToken within config/initializers/devise.rb
# fields will be set in TokensController and OmniauthCallbacksController
module IdentityManagementExtension
  extend ActiveSupport::Concern

  included do

    class OtpTooManyTries < StandardError
      def message
        I18n.t('auth.error.otp_too_many_tries')
      end
    end

    include Mongoid::Persistable::Incrementable

    # token will be revoked after this many wrong OTPs
    OTP_MAX_TRIES = 3
    # after first login this many seconds to supply OTP before token expires
    OTP_TIME_TO_AUTHENTICATE = 300
    # Allow some seconds of drift (accepts shortly expired code) to compensate server clock drift
    OTP_DRIFT = 60

    field :im_app, type: String
    field :im_ip, type: String
    field :im_navigator, type: String
    field :im_location, type: String
    field :im_device, type: String

    field :im_otp_required, type: Mongoid::Boolean
    field :im_otp_provided, type: Mongoid::Boolean
    field :im_otp_tries, type: Integer, default: 0

    before_create :fill_computed
    before_save :fill_computed

    before_save do
      # set boolean flag that requires checking if an otp
      # was provided for the token which is checked during JsonApiController#authorize
      if !self.im_otp_required.eql?(false) && self.user.otp_enabled?
        self.im_otp_required = true
         # limit time to enter an otp before the token expires
        if self.im_otp_provided
          self.expires_in = Doorkeeper.configuration.access_token_expires_in
        else
          self.expires_in = Doorkeeper.configuration.access_token_expires_in #OTP_TIME_TO_AUTHENTICATE
        end
      else
        self.im_otp_required = false
      end
    end

    belongs_to :user, foreign_key: :resource_owner_id, optional: true

    after_save do
      if (self.im_ip_changed? || self.im_navigator_changed? || self.im_app_changed?)
        AccountActivity.where(token_id: self.id, user_id: self.resource_owner_id)
        .first_or_create(created_at: self.created_at)
        .update_attributes(
          app: self.im_app,
          ip: self.im_ip,
          navigator: self.im_navigator,
          updated_at: self.updated_at,
          location: self.im_location,
          device: self.im_device
        )
      end
    end

    # helper for otp to check if this access token is valid
    # when the user has otp/mfa enabled
    def otp_satisfied?
      return true if self.im_otp_required.eql?(false)
      return true if self.im_otp_provided.eql?(true)
      false
    end

    def tries_left?
      self.im_otp_tries.to_i < OTP_MAX_TRIES
    end

    def authenticate_otp(otp)
      _success = self.user.authenticate_otp(otp.to_s, drift: OTP_DRIFT)
      if _success
        # set provided, reset tries, bump expiry to default
        self.update_attributes im_otp_provided: true, im_otp_tries: 0, expires_in: Doorkeeper.configuration.access_token_expires_in
      else
        # add counter to log failed attempts
        self.inc(im_otp_tries: 1)
        unless self.tries_left?
          self.revoke
          raise OtpTooManyTries
        end
      end
      _success
    end

    # compatability with ApplicationDocument for usage with JsonApiController
    # no effect unless needed
    def self.quickfilter(_, _opts=nil)
      criteria
    end
    def self.gridfilter(_)
      criteria
    end
    def self.paginate(_)
      criteria
    end
    def self.sorting(_)
      criteria
    end
    def self.auto_includes(_, _opts=nil)
      criteria
    end
    def self.available
      criteria
    end

  end


  Geocoder.configure(
    ip_lookup: :geoip2,
    geoip2: {
      lib: 'maxminddb', #lib: 'hive_geoip2',
      file: File.join(Rails.root, 'GeoLite2-City.mmdb'),
      service: :city
    }
  )

  def fill_computed
    self.im_location ||= self.get_location
    self.im_device ||= self.get_device
  end

  def get_location
    return if im_ip.blank?
    res = Geocoder.search(self.im_ip) rescue nil
    loc = res.try(:first)
    return if loc.nil?
    loc.language = :de
    [loc.country, loc.city].compact.reject(&:blank?).collect(&:strip).compact.join(', ').strip rescue nil
  end

  def get_device
    return if im_navigator.blank?
    browser = Browser.new(im_navigator)
    platform_name = browser.platform.name
    platform_name = 'macOS' if platform_name.eql?('Macintosh')
    device_name =  browser.device.name
    device_name = platform_name if device_name.eql?('Unknown')
    "#{browser.name} #{device_name}".strip
  end

end
