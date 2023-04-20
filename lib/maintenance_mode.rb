class MaintenanceMode
  class FetchError < StandardError; end
  class ReadOnlyMaintenanceError < StandardError; end
  class FullMaintenanceError < StandardError; end

  attr_accessor :definition

  def initialize(definition)
    self.definition = definition
  end

  def enabled?
    return false if self.definition.nil?
    self.definition[:type] != 'off'
  end

  def read_allowed?
    return true if self.definition.nil?
    self.definition[:type] != 'full'
  end

  def write_allowed?
    not enabled?
  end

  def start
    return nil if self.definition.nil?
    Time.parse(self.definition[:start])
  end

  def end
    return nil if self.definition.nil?
    return nil if self.definition[:end].nil?
    Time.parse(self.definition[:end])
  end

  def reason
    return nil if self.definition.nil?
    self.definition[:reason] # hash locale -> content
  end

  def reason_localized
    r = reason
    return nil if r.nil?
    # first try locale, then language, then fallback :en
    r[I18n.locale] || r[I18n.locale.to_s.split("-").first] || r[:en]
  end

  # @param type Type of access :read or :write
  def raise_error(type = :write)
    msg = reason_localized
    raise FullMaintenanceError.new(msg) unless read_allowed?
    raise ReadOnlyMaintenanceError.new(msg) unless write_allowed? if type == :write
  end

  # class methods
  def self.current
    MaintenanceMode.new info[:current]
  end

  def self.planned
    info[:planned].map { |elem| MaintenanceMode.new(elem) }
  end

  def self.info
    unless @running
      return {
        :current => nil,
        :planned => [],
      }.with_indifferent_access
    end

    ret = nil
    @info_mutex.synchronize do
      ret = @info
      if ret.nil?
        @info_signal.wait(@info_mutex)
        ret = @info
      end
    end
    raise "No info available" if ret.nil? # should never happen
    ret
  end

  def self.url
    ENV['MAINTENANCE_STATE_URL']
  end

  private
  @running = false # current thread running state (used for stopping)
  @thread_stop_signal = ConditionVariable.new # signal for stop thread
  @thread_stop_signal_mutex = Mutex.new # needed for signalling
  @run_thread = nil # the update thread fetching data
  @run_mutex = Mutex.new # mutex for start/stop
  @info = nil # the current info
  @info_fetched = nil # timestamp of current info
  @info_mutex = Mutex.new # mutex for info
  @info_signal = ConditionVariable.new # signal for updated info
  @fetch_interval = 30.seconds # info fetch interval
  @disable_ssl_verify = ENV["DISABLE_SSL_VERIFY"].to_s.eql?('true')

  def self.update_thread
    while @running
      info = @info
      begin
        info = fetch_info
      rescue FetchError => e
        puts e
        if info.nil?
          # polyfill info as we have no previous info
          info = {
            :current => {
              :start => Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z'),
              :end => nil,
              :reason => { :en => e.message },
              :type => "full"
            },
            :planned => []
          }.with_indifferent_access
        end
      ensure
        # if info is still nil here we have no maintenance state source url configured, so we set an empty struct
        if info.nil?
          info = {
            :current => nil,
            :planned => [],
          }.with_indifferent_access
        end
      end
      @info_mutex.synchronize do
        @info = info
        @info_fetched = Time.now
        @info_signal.broadcast
      end
      @thread_stop_signal_mutex.synchronize do
        @thread_stop_signal.wait(@thread_stop_signal_mutex, @fetch_interval)
      end
    end
  end

  def self.start
    stop
    @run_mutex.synchronize do
      @running = true
      @run_thread = Thread.new {
        update_thread
      }
    end
  end
  def self.stop
    @run_mutex.synchronize do
      @running = false
      unless @run_thread.nil?
        @thread_stop_signal_mutex.synchronize do
          @thread_stop_signal.broadcast # wake up all threads waiting
        end
        @run_thread.join
      end
    end
  end

  def self.fetch_info
    return nil if url.blank?
    target_url = URI.parse(url)
    target_path = target_url.path
    target_url.path = ""
    http = Sawyer::Agent.new(target_url.to_s) do |http|
      http.ssl.verify = false if @disable_ssl_verify
      http.options.timeout = 1 # 1 sec timeout
    end
    begin
      response = http.call(:get, target_path)
    rescue StandardError => e
      raise FetchError.new("Maintenance info can't be fetched. Error: #{e.message}")
    end
    unless response.status.to_i.eql?(200)
      raise FetchError.new("Maintenance info can't be fetched. Status = #{response.status}, Body = #{response.body}")
    end
    response.data
  end
end

at_exit do
  MaintenanceMode.stop
end

module MaintenanceModeReadOnlyConcern
  extend ActiveSupport::Concern

  included do
    before_save :check_readonly
    before_create :check_readonly
    before_update :check_readonly
    before_destroy :check_readonly

    def check_readonly
      MaintenanceMode.current.raise_error :write
    end
  end
end

# Monkeypatch for Mongoid::Document (to enforce maintenance mode)
module Mongoid::Document
  include MaintenanceModeReadOnlyConcern
end

