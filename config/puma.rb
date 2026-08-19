# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
#
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
#
port        ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
#
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the number of `workers` to boot in clustered mode.
# Workers are forked webserver processes. If using threads and workers together
# the concurrency of the application would be max `threads` * `workers`.
# Workers do not work on JRuby or Windows (both of which do not support
# processes).
#
# workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Use the `preload_app!` method when specifying a `workers` number.
# This directive tells Puma to first boot the application and load code
# before forking the application. This takes advantage of Copy On Write
# process behavior so workers use less memory.
#
preload_app!

persistent_timeout 90

puma_in_cluster_mode = false

require_relative '../lib/heap_dumper'

before_fork do
  # if we fork we're in cluster mode
  puma_in_cluster_mode = true

  # clean up memory before forking to maximize copy on write efficiency
  3.times { GC.start(full_mark: true, immediate_sweep: true) }
  GC.compact
end

before_worker_boot do
  # runs in worker context

  MaintenanceMode.start
  puts "[#{Process.pid}] Maintenance mode started."
  HeapDumper.start
end

# Worker crash reporting (cluster mode only).
#
# Runs in the master process every time a worker process is reaped, so it sees
# the actual exit status instead of guessing from a worker's boot time. Because
# preload_app! boots Rails - and with it config/initializers/sentry.rb - in the
# master before the first fork, Sentry is initialized here and the crash can be
# reported immediately.
#
# Do NOT move this back into a worker hook: worker hooks run after the fork, so
# state they set (a global, an ivar, ...) is invisible to the initializers, which
# already ran in the master while preloading. That is why the previous
# $sentry_report_worker_crash flag never reached Sentry.
after_worker_shutdown do |worker|
  status = worker.process_status # Process::Status, nil if it could not be determined

  # graceful stop (shutdown / hot restart / phased restart): puma asked the worker
  # to terminate and it exited cleanly - nothing to report
  next if worker.term? && status&.success?

  # puma sends SIGKILL itself when a worker misses its check-in (worker_timeout)
  # or overruns worker_shutdown_timeout; the OOM killer uses SIGKILL as well
  reason = if status.nil?
             'exit status unknown'
           elsif status.signaled?
             "killed by signal #{status.termsig}"
           else
             "exited with status #{status.exitstatus}"
           end
  kind = if status.nil?
           'unknown'
         elsif status.signaled?
           "signal_#{status.termsig}"
         else
           "exit_#{status.exitstatus}"
         end

  puts "[#{Process.pid}] WORKER CRASH DETECTED: worker #{worker.index} (pid #{worker.pid}) #{reason} " \
       "after #{worker.uptime.round(1)}s (booted: #{worker.booted?}, terminating: #{worker.term?})"

  next unless defined?(Sentry) && Sentry.initialized?

  # worker.term? separates "died out of nowhere" from "was asked to stop but had to
  # be killed" - keep them as two Sentry issues, the message must stay static so
  # crashes group together instead of one issue per pid
  message = worker.term? ? 'PUMA: Worker did not shut down cleanly' : 'PUMA: Worker Crash detected'

  Sentry.capture_message(
    message,
    level: :error,
    tags: { puma_worker_exit: kind },
    extra: {
      worker_index: worker.index,
      worker_pid: worker.pid,
      worker_phase: worker.phase,
      uptime_seconds: worker.uptime.round(1),
      booted: worker.booted?,
      terminating: worker.term?,
      reason: reason
    }
  )
end

before_worker_shutdown do
  # runs in each worker on shutdown
  MaintenanceMode.stop
  puts "[#{Process.pid}] Maintenance mode stopped."
  HeapDumper.stop
end

after_booted do
  # single mode callbacks for non-cluster setup, but are also called for master process in clustered mode
  unless puma_in_cluster_mode
    MaintenanceMode.start
    puts "[#{Process.pid}] Maintenance mode started."
    HeapDumper.start
  end
end

after_stopped do
  # single mode callbacks for non-cluster setup, but are also called for master process in clustered mode
  unless puma_in_cluster_mode
    MaintenanceMode.stop
    puts "[#{Process.pid}] Maintenance mode stopped."
    HeapDumper.stop
  end
end

# Periodic full GC via out_of_band (runs after a request completes, outside request cycle)
last_oob_gc = Time.now.utc

out_of_band do
  now = Time.now.utc
  if now - last_oob_gc >= 3600
    last_oob_gc = now
    GC.start(full_mark: true, immediate_sweep: true)
  end
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
