require 'rails_helper'
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

  # forks like Puma does and returns, per server, whether the worker's monitor runs
  def worker_monitor_states
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      run_hooks(:before_worker_boot)
      Mongoid.default_client.database.command(ping: 1)
      writer.write(Mongoid.default_client.cluster.servers_list.map { |s| s.monitor&.running? }.to_json)
      writer.close
      # skip at_exit hooks, they belong to the parent's RSpec run
      exit!(0) # rubocop:disable Rails/Exit
    end
    writer.close
    JSON.parse(reader.read).tap { Process.wait(pid) }
  end

  after { Mongoid.reconnect_clients }

  it 'gives a worker forked from a connected master a monitored cluster' do
    # connect before the fork, as happens once anything touches Mongo at boot
    Mongoid.default_client.database.command(ping: 1)
    run_hooks(:before_fork)

    expect(worker_monitor_states).to be_present.and all(be(true))
  end
end
