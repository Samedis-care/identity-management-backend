require 'net/http'

class Api::SentryController < ApplicationController

  def tunnel
    envelope = request.body.read

    piece = envelope.split("\n").first
    header = JSON.parse(piece)

    dsn = URI.parse(header['dsn'])
    project_id = dsn.path.tr('/', '')

    header['forwarded_for'] = request.remote_ip
    envelope = JSON.generate(header) + envelope[piece.length..]

    raise "Invalid sentry hostname: #{dsn.hostname}" if dsn.hostname != sentry_host
    raise "Invalid sentry project id: #{project_id}" unless project_id.present?

    upstream_sentry_url = "https://#{sentry_host}/api/#{project_id}/envelope/"
    Net::HTTP.post(URI(upstream_sentry_url), envelope)

    head(:ok)
  rescue => e
    # handle exception in your preferred style,
    # e.g. by logging or forwarding to server Sentry project
    Rails.logger.error('error tunneling to sentry')
  end

  private
  def sentry_host
    @sentry_host ||= URI.parse(ENV['SENTRY_DSN_FRONTEND']).host
  end

end