require 'digest'

class CustomAuthProvider < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps

  field :domain, type: String
  field :checksum, type: String
  field :client_id, type: String
  field :client_secret, type: String
  field :host, type: String

  field :tmp_saved_code_verifier, type: String # @TODO !! only temporary for testing

  validates :domain, uniqueness: true

  before_save :generate_checksum

  index({ domain: 1 }, { unique: true })
  index({ checksum: 1 }, { unique: true })

  def self.hints
    pluck(:checksum).compact
  end

  def code_verifier
    @code_verifier ||= begin
      self.set tmp_saved_code_verifier: SecureRandom.urlsafe_base64(32)
      self.tmp_saved_code_verifier
    end
  end

  def code_challenge
    puts "=" * 80
    puts "using code_verifier: #{code_verifier}"
    puts "=" * 80
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
      prompt: :consent
    }
  end

  def passthru_uri(code_verifier: nil, state: nil, login_hint: nil)
    _query_params = self.query_params
    _query_params = _query_params.merge(login_hint:) if login_hint.present?
    _query_params = _query_params.merge(state:) if state.present?
    _query_params[:state] ||= {
      app: 'samedis-care',
      redirect_host: 'https://localhost.samedis.care'
    }.to_json
    URI::HTTPS.build(host:, path: , query: _query_params.to_query)
  end

  def user_info(code)
    uri = URI::HTTPS.build(host:, path: '/oauth2/token')

    params = {
      code:,
      code_verifier: tmp_saved_code_verifier,
      redirect_uri:,
      grant_type: 'authorization_code'
    }

    _authorization = "Basic #{Base64.strict_encode64([client_id, client_secret].join(':'))}"

    response = Faraday.post(uri) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = _authorization
      req.body = params.to_json
      ap req
    end

    user_info = JSON.parse(response.body) rescue nil
    puts "=" * 80
    ap user_info
    puts "=" * 80
    raise "failed (#{response.status}): #{response.body}" unless user_info

    _decoded = JWT.decode(user_info['id_token'], nil, false)
    puts "=" * 80
    ap _decoded
    puts "=" * 80
    _decoded[0]
  end


  private

  def generate_checksum
    self.checksum = Digest::MD5.hexdigest(domain)
  end

end