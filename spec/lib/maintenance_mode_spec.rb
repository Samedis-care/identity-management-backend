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
      expect(described_class.info[:current]).to be_nil
    end

    it 'is a no-op from a trap context when it was never started' do
      expect(in_trap_context { described_class.stop }).to be_nil
    end
  end
end
