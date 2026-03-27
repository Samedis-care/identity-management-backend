require 'digest'

# Enterprise SSO via OAuth2/OIDC for customer-managed Identity Providers.
#
# Supports OIDC Auto-Discovery: set `issuer_url` and all endpoint URLs
# (authorize, token, userinfo, jwks) are populated automatically on save.
# Manual overrides are preserved — only blank fields get auto-filled.
#
# Tested with: Azure AD, Keycloak, Okta, Auth0, WSO2 Identity Server.
#
# Minimal setup with discovery:
#
#   CustomAuthProvider.create!(
#     domain: 'uniklinik.example.de',
#     issuer_url: 'https://auth.uniklinik.example.de/oauth2/token',  # WSO2 IS
#     client_id: 'from-customer',
#     client_secret: 'from-customer'
#   )
#
# Minimal setup with Azure AD:
#
#   CustomAuthProvider.create!(
#     domain: 'kunde.de',
#     issuer_url: 'https://login.microsoftonline.com/{tenant-id}/v2.0',
#     client_id: 'from-azure-portal',
#     client_secret: 'from-azure-portal'
#   )
#
class CustomAuthProvider < ApplicationDocument
  class UntrustedEmailError < StandardError; end
  class FailedAuthError < StandardError; end

  include Mongoid::Document
  include Mongoid::Timestamps

  DISCOVERY_CACHE_TTL = 1.hour

  field :domain, type: String
  field :client_id, type: String
  field :client_secret, type: String
  field :host, type: String
  field :issuer_url, type: String
  field :trusted_email_domains, type: Array
  field :scope, type: String
  field :authorize_url, type: String
  field :token_url, type: String
  field :userinfo_url, type: String
  field :jwks_uri, type: String
  field :userinfo_schema, type: Hash
  field :userinfo_mapping, type: Hash
  field :claims

  validates :domain, uniqueness: true
  validate :unique_trusted_email_domains

  before_save :auto_discover!, if: -> { issuer_url_changed? || (issuer_url.blank? && host_changed?) }

  attr_accessor :code_verifier

  index({ domain: 1 }, { unique: true })

  # Auto-discover: if issuer_url is set, use it directly. Otherwise probe
  # common OIDC discovery paths based on host.
  def auto_discover!
    if issuer_url.present?
      discover!
    elsif host.present?
      probe_and_discover!
    end
  end

  # Fetch OIDC discovery document and populate endpoint URLs automatically.
  # Only fields that are blank get overwritten — manual overrides are preserved.
  def discover!
    return unless issuer_url.present?

    config = discovery_config
    return if config.nil?

    self.host           = URI.parse(config['authorization_endpoint']).host if host.blank? && config['authorization_endpoint']
    self.authorize_url  = URI.parse(config['authorization_endpoint']).path if read_attribute(:authorize_url).blank? && config['authorization_endpoint']
    self.token_url      = URI.parse(config['token_endpoint']).path if read_attribute(:token_url).blank? && config['token_endpoint']
    self.userinfo_url   = config['userinfo_endpoint'] if read_attribute(:userinfo_url).blank? && config['userinfo_endpoint']
    self.jwks_uri       = config['jwks_uri'] if jwks_uri.blank? && config['jwks_uri']
    self.scope          = config['scopes_supported']&.intersection(%w[openid profile email])&.join(' ') if read_attribute(:scope).blank? && config['scopes_supported']
  end

  # Probe common OIDC discovery paths when only host is known.
  # Sets issuer_url on first successful hit, then runs discover!.
  DISCOVERY_PROBES = [
    '/.well-known/openid-configuration',                           # Standard OIDC
    '/oauth2/token/.well-known/openid-configuration',              # WSO2 Identity Server
    '/oauth2/oidcdiscovery/.well-known/openid-configuration',      # WSO2 alternative
    '/realms/master/.well-known/openid-configuration',             # Keycloak (master realm)
    '/auth/realms/master/.well-known/openid-configuration',        # Keycloak (legacy path)
    '/.well-known/openid-configuration/',                          # trailing slash variant
  ].freeze

  def probe_and_discover!
    conn = Faraday.new { |f| f.response :follow_redirects, limit: 3 }

    DISCOVERY_PROBES.each do |path|
      url = "https://#{host}#{path}"
      response = conn.get(url)
      next unless response.status == 200 && response.body.length > 10

      config = JSON.parse(response.body)
      next unless config['issuer'].present?

      self.issuer_url = config['issuer']
      Rails.logger.info("OIDC discovery auto-detected issuer: #{issuer_url} via #{path}")
      discover!
      return
    rescue JSON::ParserError, Faraday::Error
      next
    end

    Rails.logger.info("OIDC discovery: no discovery endpoint found for host #{host}")
  end

  # Fetch and cache the OIDC discovery document
  def discovery_config
    cache_key = "oidc_discovery:#{issuer_url}"
    Rails.cache.fetch(cache_key, expires_in: DISCOVERY_CACHE_TTL) do
      discovery_url = "#{issuer_url.chomp('/')}/.well-known/openid-configuration"
      response = Faraday.get(discovery_url)
      unless response.status == 200
        Rails.logger.warn("OIDC discovery failed for #{issuer_url}: HTTP #{response.status}")
        next nil
      end
      JSON.parse(response.body)
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("OIDC discovery failed for #{issuer_url}: #{e.message}")
      nil
    end
  end

  def unique_trusted_email_domains
    return unless self.class.where(:_id.ne => id, :trusted_email_domains.in => trusted_email_domains).exists?

    errors.add(:trusted_email_domains, 'A provider for one of the trusted email domains already exists') and throw(:abort)
  end

  def create_code_verifier!
    self.code_verifier = SecureRandom.urlsafe_base64(32)
  end

  def code_challenge
    code_verifier || create_code_verifier!
    Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier)).tr('=', '')
  end

  def code_challenge_method
    'S256'
  end

  # the callback uri forwared to the remote oauth2 server
  def redirect_uri
    url_helpers.v1_user_custom_omniauth_callback_url(provider: domain) #, host: 'https://dev.ident.services')
  end

  # the initial url as POST target that will redirect to the remote host
  def authorize_uri
    url_helpers.v1_user_custom_omniauth_authorize_url(provider: domain)
  end

  def response_type
    'code'
  end

  def scope
    super.presence || 'openid profile email'
  end

  def authorize_url
    super.presence || '/oauth2/authorize'
  end

  def token_url
    super.presence || '/oauth2/token'
  end

  # microsoft does not have this endpoint
  # set to 'https://graph.microsoft.com/v1.0/me'
  # to get the AD data which will automatically be mapped
  # to the proper keys via #map_userinfo
  def userinfo_url
    super.presence || '/oauth2/userinfo'
  end

  def userinfo_host
    URI.parse(userinfo_url).host || host
  end

  def userinfo_path
    URI.parse(userinfo_url).path
  end

  def userinfo_schema
    return {} if is_microsoft?

    (super || { schema: :openid }).presence
  end

  def self.default_mapping
    {
      email: %w(email sub mail),
      first_name: %w(given_name givenName),
      last_name: %w(family_name surname),
      name:  %w(name displayName),
      sub: %w(sub userPrincipalName)
    }
  end

  def userinfo_mapping
    (super || self.class.default_mapping).symbolize_keys
  end

  def map_userinfo(userinfo)
    mapped_userinfo = {}
    userinfo_mapping.each do |k,v|
      mapped_userinfo[k.to_sym] = [v].flatten.collect do |mapping|
        userinfo[mapping]
      end.reject(&:blank?).first
    end
    mapped_userinfo
  end

  def query_params
    { 
      client_id:,
      redirect_uri:,
      response_type:,
      scope:,
      code_challenge:,
      code_challenge_method:
      # prompt: :consent
    }
  end

  def claims
    super || {
      userinfo: {
        given_name: { essential: true },
        email: { essential: true }
      }
    }
  end

  def passthru_uri(code_verifier: nil, state: nil, login_hint: nil)
    _query_params = self.query_params
    _query_params = _query_params.merge(login_hint:) if login_hint.present?
    _query_params = _query_params.merge(state:) if state.present?
    _query_params[:state] ||= { app: 'identity-management', redirect_host: ENV['WEB_APP_HOST'] }.to_json

    URI::HTTPS.build(host:, path: authorize_url, query: _query_params.to_query)
  end

  def access_token(code, code_verifier: nil)
    if code_verifier.blank?
      e = FailedAuthError.new('Missing code_verifier')
      raise e
    end

    uri = URI::HTTPS.build(host:, path: token_url)

    params = {
      code:,
      code_verifier:,
      redirect_uri:,
      grant_type: 'authorization_code',
      scope:,
      claims:
    }

    _authorization = "Basic #{Base64.strict_encode64([client_id, client_secret].join(':'))}"

    # must be form based as Microsoft does not support JSON requests
    response = Faraday.post(uri) do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.headers['Authorization'] = _authorization
      req.body = URI.encode_www_form(params)
    end

    unless response.status.eql?(200)
      c = Sentry::Breadcrumb.new(
        category: 'access_token',
        message: "Fetching access_token for #{domain} failed with HTTP status #{response.status}.",
        level: 'warn',
        data: response.body
      )
      Sentry.add_breadcrumb(c)
      e = FailedAuthError.new(I18n.t('json_api.oauth_failed', host:))
      Sentry.capture_exception(e)
      raise e
    end

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Sentry.capture_exception(e)
      raise FailedAuthError, I18n.t('json_api.oauth_failed', host:)
    end
  end

  def is_microsoft?
    userinfo_host.eql?('graph.microsoft.com')
  end

  def user_info(access_token)
    # special handling for microsoft
    query = userinfo_schema&.to_query
    uri = URI::HTTPS.build(host: userinfo_host, path: userinfo_path, query:)

    _authorization = "Bearer #{access_token}"

    # microsoft does not care aput content-type json
    # and will ignore schema requests in query as well
    # as claims
    response = Faraday.get(uri) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = _authorization
      req.body = { claims: }.to_json unless is_microsoft?
    end

    unless response.status == 200
      raise FailedAuthError, "user_info request failed (#{response.status})"
    end

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Sentry.capture_exception(e)
      raise FailedAuthError, "user_info parse failed (#{response.status})"
    end
  end

  # For Omniauth Aut Hash Schema 1.0 compatibility
  # the callback will store this in request.env['omniauth.auth']
  # so the default `do_oauth` can be used from there onwards
  # https://github.com/omniauth/omniauth/wiki/Auth-Hash-Schema
  def auth(token)
    userinfo = user_info(token['access_token'])

    mapped_userinfo = map_userinfo(userinfo)

    expires = token['expires_in'].to_i.positive?
    expires_at = expires ? token['expires_in'].to_i.seconds.from_now : nil

    unless email_trusted?(mapped_userinfo[:email])
      Sentry.capture_message("user_info from oauth: #{userinfo.inspect}")

      c = Sentry::Breadcrumb.new(
        category: 'user_info',
        message: "Fetching user_info for #{domain} returned no or only untrusted email.",
        level: 'warn',
        data: userinfo
      )
      Sentry.add_breadcrumb(c)
      e = UntrustedEmailError.new(I18n.t('json_api.oauth_untrusted_email', email: mapped_userinfo[:email], host:))
      Sentry.capture_exception(e)
      raise e
    end

    OpenStruct.new(
      provider: host,
      uid: "#{mapped_userinfo[:sub]}@#{host}",
      credentials: OpenStruct.new(
        token: token['access_token'],
        refresh_token: token['refresh_token'],
        secret: client_secret,
        expires:,
        expires_at:
      ),
      info: OpenStruct.new(
        email: mapped_userinfo[:email],
        name: mapped_userinfo[:name],
        first_name: mapped_userinfo[:first_name],
        last_name: mapped_userinfo[:last_name]
      ),
      extra: OpenStruct.new(
        raw_info: token.to_json
      )
    )
  end

  def trusted_domains
    @trusted_domains ||= [domain, trusted_email_domains].flatten.compact
                          .collect(&:downcase).collect(&:strip).compact.uniq
  end

  def trusted_domain_checksums
    @trusted_domain_checksums ||= trusted_domains.collect { |d| Digest::MD5.hexdigest(d) }
  end

  def email_trusted?(email)
    return false unless !!(email.to_s =~ URI::MailTo::EMAIL_REGEXP)

    trusted_domains.include?(email.to_s.split('@').last&.downcase)
  end

end
