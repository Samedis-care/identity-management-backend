require 'aws-sdk-s3'
require 'parallel'

module ApacMigration
  # Copies Shrine S3 objects (tenant/actor images + user avatars) of the
  # migrated set onto the APAC bucket. Source = the app's existing AWS_S3_*
  # config; target = runtime ENV TARGET_S3_* (never committed).
  #
  # Only ever touches keys extracted from already-migrated documents' image_data,
  # so it cannot copy EU objects. Idempotent: skips keys already on the target.
  class S3Copier
    attr_reader :dry_run, :threads, :stats

    def initialize(dry_run: false, threads: 4)
      @dry_run = dry_run
      @threads = threads
      @stats   = Hash.new(0)
    end

    # Recursively collect every Shrine storage location from an image_data hash.
    # Handles the original (top-level id+storage), nested "derivatives", and the
    # flat versions_compatibility form ({ "large" => { "id" => ... }, ... }).
    def self.keys_from(image_data)
      return [] if image_data.blank?

      data = image_data.is_a?(String) ? (JSON.parse(image_data) rescue {}) : image_data
      collect_ids(data).uniq
    end

    def self.collect_ids(node)
      case node
      when Hash
        ids = []
        ids << node['id'] if node['id'].is_a?(String) && node.key?('storage')
        node.each_value { |value| ids.concat(collect_ids(value)) }
        ids
      when Array
        node.flat_map { |value| collect_ids(value) }
      else
        []
      end
    end

    def source_bucket
      @source_bucket ||= ENV['AWS_S3_BUCKET'].presence || abort('AWS_S3_BUCKET (source) is not configured.')
    end

    def target_bucket
      @target_bucket ||= ENV['TARGET_S3_BUCKET'].presence ||
                         abort('TARGET_S3_BUCKET is required (runtime ENV, never committed).')
    end

    def buckets_summary
      {
        source: ENV['AWS_S3_BUCKET'].presence || '(AWS_S3_BUCKET unset)',
        target: ENV['TARGET_S3_BUCKET'].presence || '(TARGET_S3_BUCKET unset)'
      }
    end

    # Verifies the target bucket exists and is reachable with the given creds.
    def ping_target!
      target_client.head_bucket(bucket: target_bucket)
      true
    end

    # The region the target client actually resolved to (for display).
    def target_region
      target_client.config.region
    end

    def copy_keys(keys)
      keys = keys.uniq
      # Force client init outside the thread pool to avoid a memoization race.
      source_client
      unless dry_run
        target_client
        target_bucket
        source_bucket
      end

      mutex = Mutex.new
      parallel_opts = { in_threads: dry_run ? 1 : threads }
      parallel_opts[:progress] = 'Copying S3 objects' unless dry_run
      Parallel.each(keys, **parallel_opts) do |key|
        result = copy_one(key)
        mutex.synchronize { stats[result] += 1 }
      end
      stats
    end

    private

    def copy_one(key)
      return :would_copy if dry_run
      return :skipped if exists_on_target?(key)

      object = source_client.get_object(bucket: source_bucket, key: key)
      target_client.put_object(
        bucket: target_bucket,
        key: key,
        body: object.body,
        content_type: object.content_type
      )
      :copied
    rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
      :missing_source
    end

    def exists_on_target?(key)
      target_client.head_object(bucket: target_bucket, key: key)
      true
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::Forbidden
      # NotFound → not there yet. Forbidden → creds lack ListBucket/GetObject, so
      # existence is indeterminable; treat as "copy it" (PutObject overwrites,
      # so re-uploading is harmless and keeps the run idempotent).
      false
    end

    def source_client
      @source_client ||= build_client(
        bucket: source_bucket,
        region: ENV['AWS_S3_REGION'],
        access_key_id: ENV['AWS_ACCESS_KEY_ID'],
        secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
        endpoint: ENV['AWS_S3_ENDPOINT']
      )
    end

    def target_client
      @target_client ||= build_client(
        bucket: target_bucket,
        region: ENV['TARGET_S3_REGION'],
        access_key_id: ENV['TARGET_S3_ACCESS_KEY_ID'],
        secret_access_key: ENV['TARGET_S3_SECRET_ACCESS_KEY'],
        endpoint: ENV['TARGET_S3_ENDPOINT']
      )
    end

    # Builds an S3 client pinned to the bucket's ACTUAL region. For AWS we
    # auto-detect the region (so a wrong/missing *_S3_REGION can't cause the
    # HTTP 301 "PermanentRedirect" you get when the endpoint region mismatches);
    # for custom endpoints we trust the given region.
    def build_client(bucket:, region:, access_key_id:, secret_access_key:, endpoint:)
      creds = {
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        endpoint: endpoint.presence
      }.compact

      resolved =
        if endpoint.present?
          region.presence || 'us-east-1'
        else
          discover_region(bucket, creds) || region.presence || 'us-east-1'
        end

      Aws::S3::Client.new(**creds.merge(region: resolved))
    end

    # Returns a bucket's region via the x-amz-bucket-region response header,
    # which S3 sets even on the 301/403 from a region-agnostic probe.
    def discover_region(bucket, creds)
      probe = Aws::S3::Client.new(**creds.merge(region: 'us-east-1'))
      region_from(probe.head_bucket(bucket: bucket).context)
    rescue Aws::S3::Errors::ServiceError => e
      region_from(e.context)
    rescue StandardError
      nil
    end

    def region_from(context)
      context&.http_response&.headers&.[]('x-amz-bucket-region').presence
    end
  end
end
