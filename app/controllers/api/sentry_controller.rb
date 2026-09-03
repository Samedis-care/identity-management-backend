require 'net/http'

class Api::SentryController < ApplicationController

  def tunnel
    # raw_post (not body.read) so the envelope survives rack parameter parsing
    envelope = request.raw_post.to_s

    piece = envelope.split("\n").first
    header = JSON.parse(piece) rescue {}

    dsn = URI.parse(header['dsn'] || '')
    project_id = dsn.path.tr('/', '')

    header['forwarded_for'] = request.remote_ip
    # binary concat, envelopes may contain attachments/non ascii payloads
    envelope = JSON.generate(header).b + envelope[piece.to_s.length..].to_s.b

    raise 'Sentry tunnel is not configured' if sentry_host.blank? || sentry_project_ids.empty?
    raise "Invalid sentry hostname: #{dsn.hostname}" if dsn.hostname != sentry_host
    raise "Invalid sentry project id: #{project_id}" unless sentry_project_ids.include?(project_id)

    upstream_sentry_uri = URI("https://#{sentry_host}/api/#{project_id}/envelope/")

    response = nil

    # /api/error-reporting is unauthenticated and forwards synchronously, so the request
    # slot has to be given up quickly. sentry ingest answers well below a second, the load
    # balancer cuts the request at 60s. write_timeout matters too, its default is also 60s
    Net::HTTP.start(upstream_sentry_uri.host, upstream_sentry_uri.port,
                    open_timeout: 2,
                    write_timeout: 5,
                    read_timeout: 5,
                    use_ssl: upstream_sentry_uri.scheme.eql?('https')) do |http|
      upstream_request = Net::HTTP::Post.new(upstream_sentry_uri.path)
      upstream_request['Content-Type'] = 'application/x-sentry-envelope'
      upstream_request.body = envelope

      response = http.request(upstream_request)
    end

    if response.code.to_i == 200
      head :ok
    else
      render plain: response.body, status: response.code.to_i
    end
  rescue StandardError => e
    render_jsonapi_error(e.message, 'sentry_tunnel_error', 500, meta: {}, exception: e)
  end

  private

  # the frontend DSN defines both the allowed sentry host and the allowed project id,
  # e.g. https://<public key>@sentry.domain.local/2 => host: sentry.domain.local, project id: 2
  def sentry_dsn
    @sentry_dsn ||= URI.parse(ENV['SENTRY_DSN_FRONTEND'].to_s) rescue URI.parse('')
  end

  def sentry_host
    @sentry_host ||= sentry_dsn.host
  end

  def sentry_project_ids
    @sentry_project_ids ||= [sentry_dsn.path.to_s.tr('/', '')].reject(&:blank?)
  end

end
