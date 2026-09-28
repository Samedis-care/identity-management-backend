require 'rails_helper'
require 'io/wait'
require 'puma/configuration'

# Issue #3068 — Puma workers inherit the master's Mongo client through
# preload_app!, and its SDAM monitor threads do not survive the fork: the
# worker's topology freezes and never finds a new primary after a failover
# (samedis-care-backend outage of 2026-09-28, #3067).
describe 'config/puma.rb fork hooks' do # rubocop:disable RSpec/DescribeClass
  let(:puma_options) do
    config = Puma::Configuration.new(config_files: [Rails.root.join('config/puma.rb').to_s])
    config.load
    config.clamp
    config.options
  end

  def run_hooks(name)
    Array(puma_options[name]).each { |hook| hook[:block].call }
  end

  def monitor_states
    Mongoid.default_client.cluster.servers_list.map { |s| s.monitor&.running? }
  end

  # Forks like Puma does and returns what the child reported: its monitor states,
  # or the error it died with. A wedged child is killed instead of hanging the suite.
  def fork_worker(timeout: 30)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      begin
        run_hooks(:before_worker_boot)
        Mongoid.default_client.database.command(ping: 1)
        writer.write({ monitors: monitor_states }.to_json)
      rescue Exception => e # rubocop:disable Lint/RescueException
        writer.write({ error: "#{e.class}: #{e.message}" }.to_json)
      end
      writer.close
      # skip at_exit hooks, they belong to the parent's RSpec run
      exit!(0) # rubocop:disable Rails/Exit
    end
    writer.close
    unless reader.wait_readable(timeout)
      Process.kill(:KILL, pid)
      Process.wait(pid)
      return { 'error' => "child did not report within #{timeout}s" }
    end
    payload = reader.read
    _, status = Process.wait2(pid)
    payload.present? ? JSON.parse(payload) : { 'error' => "child exited #{status.inspect} without reporting" }
  end

  before do
    puma_options # loads config/puma.rb, which requires HeapDumper
    # the hook runs for real, but must not start threads or reach the maintenance endpoint
    allow(MaintenanceMode).to receive(:start)
    allow(HeapDumper).to receive(:start)
    # connect before the fork, as happens once anything touches Mongo at boot
    Mongoid.default_client.database.command(ping: 1)
  end

  after { Mongoid.reconnect_clients }

  it 'stops the master\'s monitors before any worker is forked' do
    run_hooks(:before_fork)

    expect(monitor_states).to all(be(false))
  end

  it 'gives a worker forked from a connected master a monitored cluster' do
    run_hooks(:before_fork)

    expect(fork_worker).to include('monitors' => be_present.and(all(be(true))))
  end
end
