require 'digest'

class CustomAuthProvider < ApplicationDocument
  class UntrustedEmailError < StandardError; end
  class FailedAuthError < StandardError; end

  include Mongoid::Document
  include Mongoid::Timestamps

  field :domain, type: String
  field :client_id, type: String
  field :client_secret, type: String
  field :host, type: String
  field :trusted_email_domains, type: Array
  field :scope, type: String
  field :authorize_url, type: String
  field :token_url, type: String
  field :userinfo_url, type: String
  field :claims

  validates :domain, uniqueness: true
  validate :unique_trusted_email_domains

  attr_accessor :code_verifier

  index({ domain: 1 }, { unique: true })

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

  def userinfo_url
    super.presence || '/oauth2/userinfo'
  end

  def userinfo_host
    URI.parse(userinfo_url).host || host
  end

  def userinfo_path
    URI.parse(userinfo_url).path
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
    raise FailedAuthError.new("Missing code_verifier") unless code_verifier.present?

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

    response = Faraday.post(uri) do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.headers['Authorization'] = _authorization
      req.body = URI.encode_www_form(params)  # Correctly encode params as x-www-form-urlencoded
    end

    Sentry.add_breadcrumb(Sentry::Breadcrumb.new(
      category: "custom_auth_provider",
      message: "Fetching an oauth access_token for #{domain} returned status: #{response.status}",
      level: "warn",
      data: response.body
    ))

    unless response.status.eql?(200)
      return response
      e = FailedAuthError.new(I18n.t('json_api.oauth_failed', host:))
      Sentry.capture_exception(e)
      raise e
    end
    user_info = JSON.parse(response.body) rescue nil

    user_info
  end

  def jwt_decode(token)
    JWT.decode(token, nil, false)
  end

  def user_info(access_token)
    uri = URI::HTTPS.build(host: userinfo_host, path: userinfo_path, query: { schema: :openid }.to_query)

    _authorization = "Bearer #{access_token}"

    # microsoft does not care aput content-type json
    # and will ignore schema requests in query as well
    # as claims
    response = Faraday.get(uri) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = _authorization
      req.body = { claims: }.to_json
    end

    user_info = JSON.parse(response.body) rescue nil

    raise "failed (#{response.status}): #{response.body}" unless user_info

    user_info
  end

  # For Omniauth Aut Hash Schema 1.0 compatibility
  # the callback will store this in request.env['omniauth.auth']
  # so the default `do_oauth` can be used from there onwards
  # https://github.com/omniauth/omniauth/wiki/Auth-Hash-Schema
  def auth(token)
    user_info = user_info(token['access_token'])

    email = user_info['email'] || user_info['sub'] || user_info['mail']
    first_name = user_info['given_name']
    last_name = user_info['family_name']
    _name = user_info['name'] || "#{first_name} #{last_name}"
    expires = token['expires_in'].to_i > 0
    expires_at = expires ? token['expires_in'].to_i.seconds.from_now : nil

    unless email_trusted?(email)
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(
        category: "user_info",
        message: "Fetching user_info for #{domain} returned no or only untrusted email.",
        level: "warn",
        data: user_info
      ))
      e = UntrustedEmailError.new(I18n.t('json_api.oauth_untrusted_email', email:, host:))
      Sentry.capture_exception(e)
      raise e
    end

    OpenStruct.new(
      provider: host,
      uid: "#{user_info['sub']}@#{host}",
      credentials: OpenStruct.new(
        token: token['access_token'],
        refresh_token: token['refresh_token'],
        secret: client_secret,
        expires:,
        expires_at:
      ),
      info: OpenStruct.new(
        email:,
        name: _name,
        first_name:,
        last_name:
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