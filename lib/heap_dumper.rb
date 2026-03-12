require 'rbtrace'
require 'objspace'
require 'aws-sdk-s3'
require 'socket'

class HeapDumper
  def self.dumping_thread
    s3 = Aws::S3::TransferManager.new(
      client: Aws::S3::Client.new(
        region: ENV['AWS_S3_REGION'],
        access_key_id: ENV['AWS_ACCESS_KEY_ID'],
        secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
        endpoint: ENV['AWS_S3_ENDPOINT'],
        force_path_style: ENV['AWS_S3_FORCE_PATH_STYLE'] == 'true'
      )
    )
    hostname = Socket.gethostname
    pid = Process.pid

    while @running
      filename = "heap-#{hostname}-#{pid}-#{Time.now.iso8601}.dump"
      filepath = "./tmp/#{filename}"

      GC.start
      GC.start

      begin
        File.open(filepath, 'w') do |f|
          ObjectSpace.dump_all(output: f)
        end

        s3.upload_file(filepath, bucket: ENV['AWS_S3_BUCKET'], key: "heap_dumps/#{filename}")

        Rails.logger.info("[HeapDump-#{pid}] success: #{filename}")
      rescue StandardError => e
        Rails.logger.error("[HeapDump-#{pid}] Failed: #{e.class} #{e.message}")
      ensure
        File.delete(filepath)
      end

      @thread_stop_signal_mutex.synchronize do
        @thread_stop_signal.wait(@thread_stop_signal_mutex, @dump_interval)
      end
    end
  end

  def self.start
    stop
    return unless ENV['HEAP_DUMPING'] == 'true'

    ObjectSpace.trace_object_allocations_start

    @run_mutex.synchronize do
      @running = true
      @run_thread = Thread.new do
        dumping_thread
      end
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
        @run_thread = nil
      end
    end
    ObjectSpace.trace_object_allocations_stop
  end

  @running = false # current thread running state (used for stopping)
  @thread_stop_signal = ConditionVariable.new # signal for stop thread
  @thread_stop_signal_mutex = Mutex.new # needed for signalling
  @run_thread = nil # the update thread fetching data
  @run_mutex = Mutex.new # mutex for start/stop
  @dump_interval = 600 # heap dump interval

end

at_exit do
  HeapDumper.stop
end
