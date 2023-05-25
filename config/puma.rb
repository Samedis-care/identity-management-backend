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
# preload_app!

persistent_timeout 90

start_time = Time.now.to_f # captured in main process (process managing workers)
$sentry_report_worker_crash = false # global variable
on_worker_boot do
  # code run inside worker processes. workers are copies of the main process, so start_time is filled with the main process start time.
  # this code runs very early. Sentry is not initialized here, so we can't report to Sentry yet.
  now = Time.now.to_f
  if now - start_time > 5 # if time of worker start is >5 seconds (usually < 0.1 sec) after main process start
    puts "WORKER CRASH DETECTED"
    $sentry_report_worker_crash = true # this will trigger a Sentry.capture_message in sentry.rb, thus reporting the issue to Sentry after init.
  end
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
