Sentry.init do |config|
  if ENV['SENTRY_ENABLED'].present? && ENV['SENTRY_ENABLED'].to_s.downcase == "true" && ENV['SENTRY_DSN_BACKEND'].present?
    config.dsn = ENV['SENTRY_DSN_BACKEND']
  end

  config.excluded_exceptions += [
    "Puma::HttpParserError",
  ]

  config.breadcrumbs_logger = [:active_support_logger]
  config.release = "identity-management-backend@#{File.read('public/version.txt').strip rescue 'dev'}"
  config.environment = ENV['SENTRY_ENV']


  # debug output
  #config.debug = true
  #config.logger = Sentry::Logger.new(STDOUT) # default is rails logger


  # truncate all strings in hash > 4kb
  def recursive_cleanup(hash)
    hash.each do |key, value|
      next unless value.is_a? String

      hash[key] = value.truncate 4.kilobytes
    end
    hash.each_value do |value|
      recursive_cleanup(value) if value.is_a? Hash
    end
  end

  config.before_breadcrumb = lambda do |breadcrumb, _hint|
    # truncate data in breadcrumbs to ensure no megabyte long strings are sent to sentry
    # skip non matching categories
    category = breadcrumb.category
    next unless category.is_a? String
    next unless category.ends_with? '.action_controller'

    data = breadcrumb.data
    next unless data.is_a? Hash

    params = data[:params]
    next unless params.is_a? Hash

    recursive_cleanup params

    breadcrumb
  end

  config.before_send_transaction = lambda do |event, _hint|
    # @type [Sentry::TransactionEvent] event
    next unless event.is_a? Sentry::TransactionEvent

    # truncate params data in transactions
    event.spans.each do |span|
      op = span[:op]
      next unless op.is_a? String
      next unless op.ends_with? '.action_controller'

      data = span[:data]
      next unless data.is_a? Hash

      params = data[:params]
      next unless params.is_a? Hash

      recursive_cleanup params
    end

    event
  end


  # performance tracing
  traces_sample_rate = (ENV['SENTRY_PERF_SAMPLE_RATE'] || 0.0).to_f
  config.traces_sampler = lambda do |sampling_context|
    # if this is the continuation of a trace, just use that decision (rate controlled by the caller)
    next sampling_context[:parent_sampled] unless sampling_context[:parent_sampled].nil?

    # transaction_context is the transaction object in hash form
    # keep in mind that sampling happens right after the transaction is initialized
    # for example, at the beginning of the request
    transaction_context = sampling_context[:transaction_context]
    # transaction_context helps you sample transactions with more sophistication
    # for example, you can provide different sample rates based on the operation or name
    op = transaction_context[:op]
    transaction_name = transaction_context[:name]

    case op
    when 'http.server'
      # for Rails applications, transaction_name would be the request's path (env["PATH_INFO"]) instead of "Controller#action"
      case transaction_name
      when %r{api/v\d*/maintenance}
        0.0 # ignore /api/v1/maintenance (maintenance info, fetched by frontend every 30sec)
      when %r{api/error-reporting}
        0.0 # sentry tunneling
      when %r{api/}
        traces_sample_rate # sample /api/.*
      else
        0.0 # ignore /api-docs/.* and /health/.*
      end
    else
      traces_sample_rate
    end
  end
end

if $sentry_report_worker_crash # global variable, see puma.rb
  Sentry.capture_message("PUMA: Worker Crash detected")
end
