require 'rails_helper'
require Rails.root.join('lib/heap_dumper')

RSpec.describe HeapDumper do
  # Same regression as spec/lib/maintenance_mode_spec.rb
  # (Samedis-care/samedis-care-issues#2916): .stop takes @run_mutex unconditionally, so it
  # raised ThreadError in the trap context puma runs its shutdown hooks in - even with
  # HEAP_DUMPING off, where there is no dumping thread to stop in the first place.
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

  describe '.stop' do
    # HEAP_DUMPING is off here, which is how it is deployed. The shutdown hook still
    # calls .stop on every shutdown regardless.
    it 'does not raise from a trap context' do
      expect(in_trap_context { described_class.stop }).to be_nil
    end
  end
end
