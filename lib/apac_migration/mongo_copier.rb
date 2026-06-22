module ApacMigration
  # Copies raw documents from the local (EU/source) cluster into the APAC
  # target cluster. The target is reached ONLY via runtime ENV — never from
  # config/mongoid.yml — so target credentials are never committed.
  #
  # Writes are idempotent upserts by _id (replace_one upsert: true), so the
  # task can run repeatedly (vorwärmen + delta-finalize).
  class MongoCopier
    PROGRESS_EVERY = Integer(ENV.fetch('PROGRESS_EVERY', 2000))

    # IMB always writes into this database on the APAC cluster, regardless of
    # what TARGET_MONGODB_URI contains. This lets the same cluster URI (a shared
    # .env) be used by IMB and SCB — each backend pins its own database name
    # (SCB uses samediscare_apac). Overridable via ENV for non-prod targets.
    TARGET_DATABASE = ENV.fetch('TARGET_MONGODB_DATABASE', 'identity_management_apac').freeze

    attr_reader :dry_run, :limit, :updated_since, :batch_size, :threads, :stats

    def initialize(dry_run: false, limit: nil, updated_since: nil)
      @dry_run       = dry_run
      @limit         = limit
      @updated_since = updated_since
      @batch_size    = Integer(ENV.fetch('BATCH_SIZE', 500))
      @threads       = Integer(ENV.fetch('THREADS', 4))
      @stats         = Hash.new(0)
    end

    # Lazily opens (and validates) the target connection. Aborts early if the
    # ENV is missing so a dry-run still surfaces the misconfiguration.
    def target_client
      @target_client ||= begin
        uri = ENV['TARGET_MONGODB_URI']
        abort 'TARGET_MONGODB_URI is required (runtime ENV, never committed).' if uri.blank?
        # Force the database so the URI need not (and should not) carry one.
        Mongo::Client.new(uri, database: TARGET_DATABASE)
      end
    end

    # The local (source) cluster — read side, never mutated.
    def source_client
      Mongoid::Clients.default
    end

    # Live connection summary {database:, hosts:} for an open Mongo::Client.
    def connection_info(client)
      hosts = client.cluster.servers.map { |s| s.address.to_s }
      hosts = client.cluster.addresses.map(&:to_s) if hosts.empty?
      { database: client.database.name, hosts: hosts }
    rescue StandardError => e
      { database: '(unknown)', hosts: ["(#{e.class})"] }
    end

    # Target summary for display: the database is always TARGET_DATABASE (we
    # force it on connect); only the host(s) are parsed from the URI string —
    # WITHOUT any connection or DNS lookup (so a dry-run can show the target and
    # it can never hang on SRV resolution). Credentials are never exposed.
    def target_summary
      uri = ENV['TARGET_MONGODB_URI']
      return { database: TARGET_DATABASE, hosts: [] } if uri.blank?

      match = uri.match(%r{\Amongodb(?:\+srv)?://(?:[^@/]*@)?(?<hosts>[^/?]+)})
      { database: TARGET_DATABASE, hosts: match ? match[:hosts].split(',') : [] }
    end

    # Forces a connection to the target and runs a ping. Returns true or raises.
    def ping_target!
      target_client.database.command(ping: 1)
      true
    end

    # Guard against copying the source onto itself (target == source).
    def target_is_source?
      src = connection_info(source_client)
      tgt = target_summary
      src[:database] == tgt[:database] && (src[:hosts] & tgt[:hosts]).any?
    end

    # Copy documents of `model` matching `selector` into the same-named target
    # collection. `transform` may mutate each raw doc hash before write
    # (e.g. clearing EU cache fields on users). `deltaable: false` opts a
    # collection out of the UPDATED_SINCE delta filter (global reference data
    # has no meaningful updated_at boundary).
    def copy(model:, selector:, label: nil, transform: nil, deltaable: true)
      collection = model.collection.name.to_s
      name = label || collection
      sel = effective_selector(selector, deltaable)
      view = model.collection.find(sel)
      view = view.limit(limit) if limit

      # Immediate lifesign before the (potentially slow) first batch arrives.
      progress(name, 'scanning…')

      total = 0
      next_mark = PROGRESS_EVERY
      view.each_slice(batch_size) do |batch|
        docs = transform ? batch.map { |d| transform.call(d) } : batch
        write_batch(collection, docs)
        total += docs.size
        if total >= next_mark
          progress(name, "#{total} #{dry_run ? 'selected' : 'upserted'}…")
          next_mark += PROGRESS_EVERY
        end
      end

      stats[collection] += total
      # final line (trailing spaces clear any leftover \r progress text)
      puts "  #{name.ljust(28)} #{total} doc(s)#{dry_run ? ' (dry-run, not written)' : ' upserted'}        "
      total
    end

    private

    def effective_selector(selector, deltaable)
      return selector unless updated_since && deltaable

      { '$and' => [selector, { 'updated_at' => { '$gte' => updated_since } }] }
    end

    # Live, overwriting progress line (\r). Final newline is emitted by #copy.
    def progress(name, text)
      print "  #{name.ljust(28)} #{text}\r"
      $stdout.flush
    end

    def write_batch(collection, docs)
      return if dry_run || docs.empty?

      ops = docs.map do |doc|
        { replace_one: { filter: { _id: doc['_id'] }, replacement: doc, upsert: true } }
      end
      target_client[collection].bulk_write(ops, ordered: false)
    end
  end
end
