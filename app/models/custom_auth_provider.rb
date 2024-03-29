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
    'openid profile email'
  end

  def path
    '/oauth2/authorize'
  end

  def query_params
    { 
      client_id:,
      redirect_uri:,
      response_type:,
      scope: ,
      code_challenge:,
      code_challenge_method:,
      # prompt: :consent
    }
  end

  def claims
    {
      userinfo: {
        given_name: { essential: true },
        email: { essential: true },
      }
    }
  end

  def passthru_uri(code_verifier: nil, state: nil, login_hint: nil)
    _query_params = self.query_params
    _query_params = _query_params.merge(login_hint:) if login_hint.present?
    _query_params = _query_params.merge(state:) if state.present?
    _query_params[:state] ||= { app: 'identity-management', redirect_host: ENV['WEB_APP_HOST'] }.to_json

    URI::HTTPS.build(host:, path: , query: _query_params.to_query)
  end

  def access_token(code, code_verifier: nil)
    raise FailedAuthError.new("Missing code_verifier") unless code_verifier.present?

    uri = URI::HTTPS.build(host:, path: '/oauth2/token')

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
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = _authorization
      req.body = params.to_json
    end

    raise FailedAuthError.new(I18n.t('json_api.oauth_failed', host:)) unless response.status.eql?(200)
    user_info = JSON.parse(response.body) rescue nil

    user_info
  end

  def jwt_decode(token)
    JWT.decode(token, nil, false)
  end

  def user_info(access_token)
    uri = URI::HTTPS.build(host:, path: '/oauth2/userinfo', query: { schema: :openid }.to_query)

    _authorization = "Bearer #{access_token}"

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

    email = user_info['email'] || user_info['sub']
    first_name = user_info['given_name']
    last_name = user_info['family_name']
    _name = user_info['name'] || "#{first_name} #{last_name}"
    expires = token['expires_in'].to_i > 0
    expires_at = expires ? token['expires_in'].to_i.seconds.from_now : nil

    unless email_trusted?(email)
      raise UntrustedEmailError.new(I18n.t('json_api.oauth_untrusted_email', email:, host:))
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