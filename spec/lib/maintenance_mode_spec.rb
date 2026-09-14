require 'rails_helper'
require Rails.root.join('lib/maintenance_mode')

RSpec.describe MaintenanceMode do
  # Regression test for Samedis-care/samedis-care-issues#2916.
  #
  # Puma fires its after_stopped hook from inside its own SIGTERM handler, so .stop runs
  # in a trap context, where ruby refuses Mutex#synchronize outright (ThreadError). That
  # killed the whole shutdown hook - the update thread was never wound down, HeapDumper
  # was never stopped, and the process exited 1 instead of the 143 a SIGTERM normally
  # leaves behind.
  #
  # SIGUSR2 stands in for puma's SIGTERM here. The signal itself is irrelevant; what
  # matters is that the block runs as a signal handler, which is what makes it a trap
  # context - the same restriction applies no matter which signal got us there.
  def in_trap_context
    error = nil
    handled = false

    previous = Signal.trap('USR2') do
      begin
        yield
      rescue Exception => e # rubocop:disable Lint/RescueException -- whatever the handler throws is the failure we are looking for
        error = e
      end
      handled = true
    end

    begin
      Process.kill('USR2', Process.pid)
      50.times { handled ? break : sleep(0.1) }
      raise 'the USR2 handler never ran' unless handled
    ensure
      Signal.trap('USR2', previous)
    end

    error
  end

  # No maintenance state source, so the update thread's fetch short-circuits and the
  # spec neither needs the network nor ends up in a polyfilled 'full' maintenance mode
  # (which would make every Mongoid write in the process raise while it is running).
  before { allow(described_class).to receive(:url).and_return(nil) }

  after { described_class.stop }

  describe '.stop' do
    it 'winds the update thread down from a trap context instead of raising' do
      described_class.start
      expect(described_class.instance_variable_get(:@run_thread)).to be_alive

      expect(in_trap_context { described_class.stop }).to be_nil

      expect(described_class.instance_variable_get(:@run_thread)).not_to be_alive
      expect(described_class.instance_variable_get(:@running)).to be false
    end

    it 'is a no-op from a trap context when it was never started' do
      # stop leaves @run_thread set and specs run in random order, so without this the
      # example only reaches the branch it is named after on some seeds
      described_class.instance_variable_set(:@run_thread, nil)

      expect(in_trap_context { described_class.stop }).to be_nil
    end

    # A broadcast only wakes a thread that is already waiting. The update thread spends
    # part of every cycle in fetch_info instead, and a stop landing in that window used
    # to be lost - stop then blocked for the full fetch interval inside puma's SIGTERM
    # handler, long enough for docker's 10s timeout to SIGKILL the container instead.
    it 'returns promptly when the stop lands while the update thread is fetching' do
      fetching = Queue.new
      allow(described_class).to receive(:fetch_info) do
        fetching << true
        sleep 0.5
        nil
      end
      described_class.instance_variable_set(:@fetch_interval, 5.seconds)

      described_class.start
      fetching.pop # the update thread is inside fetch_info now, not waiting on the signal

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.stop
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 3
      expect(described_class.instance_variable_get(:@run_thread)).not_to be_alive
    ensure
      described_class.instance_variable_set(:@fetch_interval, 30.seconds)
    end

    # fetch_info calls URI.parse outside its own rescue, so a malformed
    # MAINTENANCE_STATE_URL kills the update thread - and Thread#join re-raises whatever
    # killed it, which would abort puma's shutdown hook exactly the way the ThreadError did.
    it 'swallows an exception the update thread died of instead of raising it at the hook' do
      allow(described_class).to receive(:fetch_info).and_raise(URI::InvalidURIError, 'bad MAINTENANCE_STATE_URL')
      report_on_exception = Thread.report_on_exception
      Thread.report_on_exception = false

      described_class.start
      run_thread = described_class.instance_variable_get(:@run_thread)
      50.times { run_thread.alive? ? sleep(0.1) : break }
      expect(run_thread).not_to be_alive

      error = nil
      expect { error = in_trap_context { described_class.stop } }.to output(/URI::InvalidURIError/).to_stderr
      expect(error).to be_nil
    ensure
      Thread.report_on_exception = report_on_exception
      described_class.instance_variable_set(:@run_thread, nil) # the after hook would join the dead thread again
    end
  end
end
