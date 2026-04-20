require 'jwt'
require 'net/http'
require 'json'

# Verifies native mobile ID tokens (JWTs) from Google, Apple, and Microsoft.
# Each provider publishes a JWKS endpoint whose public keys are used to verify
# the token's signature, audience, issuer, and expiry.
#
# Usage:
#   verifier = SocialTokenVerifier.new(provider: 'google', id_token: 'eyJ...')
#   claims = verifier.verify!  # => { 'sub' => '...', 'email' => '...', ... }
#
class SocialTokenVerifier
  class VerificationError < StandardError; end

  PROVIDERS = {
    'google' => {
      jwks_uri: 'https://www.googleapis.com/oauth2/v3/certs',
      issuers: %w[accounts.google.com https://accounts.google.com],
      audiences: -> { google_client_ids }
    },
    'apple' => {
      jwks_uri: 'https://appleid.apple.com/auth/keys',
      issuers: %w[https://appleid.apple.com],
      audiences: -> { apple_client_ids }
    },
    'microsoft' => {
      jwks_uri: 'https://login.microsoftonline.com/common/discovery/v2.0/keys',
      issuers: :microsoft_issuers,
      # Multi-tenant apps receive tenant-specific issuers (e.g. /{tenant-uuid}/v2.0)
      # even when the app is configured with tenantId "common"
      issuer_pattern: %r{\Ahttps://login\.microsoftonline\.com/[0-9a-f\-]{36}/v2\.0\z},
      audiences: -> { microsoft_client_ids }
    }
  }.freeze

  def initialize(provider:, id_token:)
    @provider = provider.to_s.downcase
    @id_token = id_token
    @config = PROVIDERS[@provider]
    raise VerificationError, "Unsupported provider: #{@provider}" unless @config
  end

  def verify!
    header = JWT.decode(@id_token, nil, false).last
    jwks = fetch_jwks
    claims = decode_and_verify(header, jwks)
    validate_claims!(claims)
    claims
  rescue JWT::DecodeError => e
    raise VerificationError, "Token decode failed: #{e.message}"
  rescue JWT::ExpiredSignature
    raise VerificationError, 'Token has expired'
  rescue JWT::InvalidIssuerError
    raise VerificationError, 'Invalid token issuer'
  rescue JWT::InvalidAudError
    raise VerificationError, 'Invalid token audience'
  end

  private

  def decode_and_verify(header, jwks)
    kid = header['kid']
    key_data = jwks['keys']&.find { |k| k['kid'] == kid }
    raise VerificationError, "No matching key found for kid: #{kid}" unless key_data

    jwk = JWT::JWK.import(key_data)
    algorithms = [header['alg'] || 'RS256']

    decoded = JWT.decode(
      @id_token,
      jwk.public_key,
      true,
      algorithms: algorithms,
      verify_expiration: true
    )
    decoded.first
  end

  def validate_claims!(claims)
    validate_issuer!(claims)
    validate_audience!(claims)
    validate_email!(claims)
  end

  def validate_issuer!(claims)
    iss = claims['iss']
    issuers = resolve_issuers
    return if issuers.include?(iss)

    issuer_pattern = @config[:issuer_pattern]
    return if issuer_pattern&.match?(iss)

    raise VerificationError, "Invalid issuer: #{iss}"
  end

  def validate_audience!(claims)
    audiences = resolve_audiences
    aud = claims['aud']
    # aud can be a string or array
    token_audiences = Array(aud)
    return if (token_audiences & audiences).any?

    raise VerificationError, "Invalid audience: #{aud}"
  end

  def validate_email!(claims)
    email = claims['email']
    raise VerificationError, 'No email in token claims' if email.blank?

    # Google provides email_verified as boolean or string
    if claims.key?('email_verified')
      verified = claims['email_verified']
      verified = verified == 'true' if verified.is_a?(String)
      raise VerificationError, 'Email not verified by provider' unless verified
    end
  end

  def resolve_issuers
    issuers = @config[:issuers]
    return send(issuers) if issuers.is_a?(Symbol)

    issuers
  end

  def resolve_audiences
    @config[:audiences].call
  end

  def fetch_jwks
    uri = URI.parse(@config[:jwks_uri])
    # Use Rails.cache to avoid fetching JWKS on every request
    cache_key = "social_token_verifier:jwks:#{@provider}"
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      response = Net::HTTP.get_response(uri)
      raise VerificationError, "Failed to fetch JWKS (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end

  # Microsoft issues tokens with tenant-specific issuers
  def microsoft_issuers
    %w[
      https://login.microsoftonline.com/common/v2.0
      https://login.microsoftonline.com/consumers/v2.0
      https://login.microsoftonline.com/organizations/v2.0
      https://sts.windows.net/
    ]
  end

  # Provider-specific audience helpers
  def self.google_client_ids
    [
      ENV['GOOGLE_OAUTH_CLIENT_ID'],
      ENV['GOOGLE_IOS_CLIENT_ID'],
      ENV['GOOGLE_ANDROID_CLIENT_ID']
    ].compact.reject(&:blank?)
  end

  def self.apple_client_ids
    [
      ENV['APPLE_CLIENT_ID'],
      ENV['APPLE_IOS_BUNDLE_ID'],
      ENV['APPLE_ANDROID_CLIENT_ID']
    ].compact.reject(&:blank?)
  end

  def self.microsoft_client_ids
    [
      ENV['AZURE_APPLICATION_CLIENT_ID'],
      ENV['AZURE_IOS_CLIENT_ID'],
      ENV['AZURE_ANDROID_CLIENT_ID']
    ].compact.reject(&:blank?)
  end
end
