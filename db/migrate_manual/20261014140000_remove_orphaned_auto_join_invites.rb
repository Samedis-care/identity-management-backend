# Deletes the orphaned auto-accept tenant invitations that samedis-care-backend's staff
# auto-join left behind in IM. See Samedis-care/samedis-care-issues#3059.
#
# Until samedis-care-backend#4477, Api::V4::Tenants::StaffsController#process_auto_join!
# POSTed a new IM auto-accept invitation on every staff sync update and overwrote the local
# invite's token, so SC no longer knows the tokens of the earlier ones and can never cancel
# them. On 2026-09-28 production IM held 832,120 such invites, 749,447 of them from the last
# 30 days. They are not just clutter: revoking login_allowed cancels only the one token SC
# knows, so an orphan for the same email and tenant stays valid for up to a year and lets a
# revoked staff member self-join the tenant on their first login.
#
# Lives in db/migrate_manual, so it is only on the migration path when MANUAL is set. Use
# db:migrate:up with an explicit VERSION, NOT db:migrate (MANUAL appends to the path, so
# db:migrate would first apply every pending regular migration on that cluster):
#
#   MANUAL=true KEEP_FILE=/secure/keep.txt EXPORT_AT=2026-10-14T10:13:40Z \
#     VERSION=20261014140000 RAILS_ENV=production bundle exec rails db:migrate:up
#
# That is a DRY RUN: it deletes nothing and finishes by raising DryRunFinished, so the
# version is NOT recorded (Mongoid::Migrator#run is a silent no-op once a version is
# recorded, which would block the real run). Read the report, then add APPLY=true and
# BACKUP_FILE=...:
#
#   MANUAL=true APPLY=true BACKUP_FILE=/secure/removed-invites.jsonl KEEP_FILE=... EXPORT_AT=... \
#     VERSION=20261014140000 RAILS_ENV=production bundle exec rails db:migrate:up
#
# Later batches (after the version is recorded) run directly via rails runner:
#
#   KEEP_FILE=... EXPORT_AT=... RAILS_ENV=production bundle exec rails runner \
#     'load Rails.root.join("db/migrate_manual/20261014140000_remove_orphaned_auto_join_invites.rb").to_s
#      RemoveOrphanedAutoJoinInvites.up'
#
# Do not set INDEXES together with MANUAL: the INDEXES branch assigns the path while the
# MANUAL branch appends, so db/migrate itself drops out.
#
# ORDER: deploy samedis-care-backend#4477 first, otherwise the nightly syncs keep minting
# orphans (~25k a night). Then export the keep list, then run this.
#
# What is deleted: every Invite that is
#   app == APP (default samedis-care; IM stores the app from the URL the invite was POSTed to)
#   invitable_type == 'tenant', auto_accept == true, not done, valid_until in the future
#   created at or before EXPORT_AT
#   and whose token is not in KEEP_FILE.
# IM does not store invited_by_id for these (it is not a permitted attribute of
# Api::V1::App::Tenant::InvitationsController), so the app is what marks them as SC's.
# Other clients of the same endpoint with auto_accept: true would match too; the report buckets
# the candidates by lifetime so that is visible (SC asks for one year, IM's default is 30 days).
#
# KEEP_FILE: one token per line, '#' comments and blank lines ignored; read-only export from
#   SC live (every token an SC Invite still references, accepted ones included). Tokens are
#   credentials for joining the tenant: never print them, and delete the file afterwards.
# EXPORT_AT: ISO 8601 time the export was taken, WITH an explicit offset (Z or +hh:mm), never in
#   the future. Invites created after it cannot be in the keep list yet and are legitimate, so
#   they are never touched; a cutoff later than the real export would delete the ones in between.
# BACKUP_FILE: required with APPLY. Every deleted invite is written here as one canonical
#   Extended JSON line (mode 0600, flushed before the delete), so a wrong run can be restored:
#     Invite.collection.insert_many(File.foreach(path).map { |l| BSON::ExtJSON.parse(l, mode: :bson) })
#   (plain JSON.parse would bring back String ids and dates that nothing finds). It contains
#   live tokens: delete it once the cleanup is verified.
#
# Knobs: LIMIT=n (delete at most n), TENANT_ID=<id> (one tenant), APP=<app name>,
#        MIN_KEEP=n (refuse to run when the keep list has fewer tokens, default 1).
# One log line per tenant. Run once per cluster - the APAC cluster has its own database and its
# own SC (production runs as RAILS_ENV=production on every cluster; point the checkout's
# mongoid.yml at the right one and check the target before applying).
class RemoveOrphanedAutoJoinInvites < Mongoid::Migration

  # raised at the end of a dry run so the version is not recorded as applied
  class DryRunFinished < StandardError; end

  BATCH = 1000

  def self.up
    config = read_config
    keep = read_keep_file(config[:keep_file], config[:min_keep])

    say "mode: #{config[:apply] ? 'APPLY (deleting)' : 'DRY RUN (nothing is deleted)'}"
    say "app=#{config[:app]} export_at=#{config[:export_at].iso8601} keep_tokens=#{keep.size} " \
        "limit=#{config[:limit].inspect} tenant=#{config[:tenant_id].inspect}"

    # done.ne: true rather than done: false, so an old document without the field still counts as open
    scope = Invite.where(app: config[:app], invitable_type: 'tenant', auto_accept: true, :done.ne => true)
                  .where(:valid_until.gt => Time.now, :created_at.lte => config[:export_at])
    scope = scope.where(tenant_id: config[:tenant_id]) if config[:tenant_id]

    stats = Hash.new(0)
    lifetimes = Hash.new(0)
    per_tenant = Hash.new { |hash, key| hash[key] = { candidates: 0, deleted: 0 } }
    pending = []

    backup = open_backup(config) if config[:apply]
    begin
      scope.only(:_id, :token, :tenant_id, :created_at, :valid_until).no_timeout.each do |invite|
        stats[:scanned] += 1
        if keep.include?(invite.token)
          stats[:kept_referenced_by_sc] += 1
          next
        end

        stats[:candidates] += 1
        per_tenant[invite.tenant_id.to_s][:candidates] += 1
        lifetimes[lifetime_bucket(invite)] += 1

        if config[:limit] && stats[:selected] >= config[:limit]
          stats[:over_limit] += 1
          next
        end

        stats[:selected] += 1
        pending << invite.id
        next unless pending.size >= BATCH

        flush(pending, backup, per_tenant, stats)
      end
      flush(pending, backup, per_tenant, stats)
    ensure
      backup&.close
    end

    report(stats, lifetimes, per_tenant, config)
    return if config[:apply]

    raise DryRunFinished, 'dry run finished, nothing was deleted and the version is not recorded - ' \
                          'add APPLY=true and BACKUP_FILE=... to delete'
  end

  # The backup file is the only way back, and the invites it holds cannot be recreated with
  # the same tokens through the API.
  def self.down
    raise Mongoid::IrreversibleMigration,
          'Deleted invites are only restorable from the BACKUP_FILE written by the run (one canonical ' \
          'Extended JSON document per line). Restore with: Invite.collection.insert_many(File.foreach(path)' \
          '.map { |line| BSON::ExtJSON.parse(line, mode: :bson) }). Plain JSON.parse would bring back ' \
          'documents with String ids and dates that nothing finds.'
  end

  def self.read_config
    app = ENV['APP'].presence || 'samedis-care'
    keep_file = ENV['KEEP_FILE'].presence or raise ArgumentError, 'KEEP_FILE is required (SC token export, one per line)'
    export_at = ENV['EXPORT_AT'].presence or raise ArgumentError, 'EXPORT_AT is required (ISO 8601 time of the SC export)'
    # Time.iso8601 reads a value without an offset in the process's local zone, so the cutoff would
    # silently move with the operator's TZ; a cutoff later than the real export deletes invites SC
    # created since, which cannot be in the keep list yet
    unless export_at.to_s.match?(/(Z|[+-]\d{2}:\d{2})\z/i)
      raise ArgumentError, "EXPORT_AT needs an explicit offset (Z or +hh:mm), got #{export_at.inspect}"
    end

    export_at = Time.iso8601(export_at.to_s).utc
    raise ArgumentError, "EXPORT_AT #{export_at.iso8601} is in the future" if export_at > Time.now
    apply = ENV['APPLY'].to_s.casecmp('true').zero?
    backup_file = ENV['BACKUP_FILE'].presence
    raise ArgumentError, 'BACKUP_FILE is required with APPLY=true' if apply && backup_file.nil?

    { app: app, keep_file: keep_file, export_at: export_at, apply: apply, backup_file: backup_file,
      limit: ENV['LIMIT'].presence&.to_i, tenant_id: ENV['TENANT_ID'].presence,
      min_keep: (ENV['MIN_KEEP'].presence || 1).to_i }
  rescue ArgumentError => e
    raise ArgumentError, "#{e.message} (EXPORT_AT must be ISO 8601, e.g. 2026-10-14T10:13:40Z)" if e.message.start_with?('invalid xmlschema')

    raise
  end

  # @return [Set<String>] tokens SC still references
  def self.read_keep_file(path, min_keep)
    raise ArgumentError, "KEEP_FILE #{path} does not exist" unless File.file?(path)

    tokens = File.foreach(path).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }.to_set
    if tokens.size < min_keep
      raise ArgumentError, "KEEP_FILE holds #{tokens.size} token(s), fewer than MIN_KEEP=#{min_keep}: " \
                           'refusing to run, an empty or truncated keep list would delete live invites'
    end

    tokens
  end

  def self.open_backup(config)
    path = config[:backup_file]
    raise ArgumentError, "BACKUP_FILE #{path} already exists, refusing to append to or overwrite it" if File.exist?(path)

    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600)
  end

  # writes the backup first, flushes it to disk, and only then deletes
  def self.flush(pending, backup, per_tenant, stats)
    return if pending.empty?

    if backup
      docs = Invite.collection.find('_id' => { '$in' => pending }).to_a
      # canonical Extended JSON, not to_json: to_json writes ObjectIds and Times as plain
      # strings, and a document restored from that is dead (Invite.valid and the tenant scope
      # never find it, its _id differs)
      docs.each { |doc| backup.puts(doc.to_extended_json(mode: :canonical)) }
      backup.flush
      backup.fsync
      result = Invite.collection.delete_many('_id' => { '$in' => docs.map { |doc| doc['_id'] } })
      deleted_ids = docs.map { |doc| doc['_id'] }
      stats[:deleted] += result.deleted_count
      tenants = docs.group_by { |doc| doc['tenant_id'].to_s }
      tenants.each { |tenant_id, rows| per_tenant[tenant_id][:deleted] += rows.size }
      say "  deleted #{result.deleted_count} (backup written first)"
      raise "backup/delete mismatch: #{deleted_ids.size} backed up, #{result.deleted_count} deleted" if result.deleted_count != deleted_ids.size
    end
    pending.clear
  end

  def self.lifetime_bucket(invite)
    return 'unknown' if invite.created_at.nil? || invite.valid_until.nil?

    # valid_until is a DateTime field, created_at a Time: subtracting them raises TypeError
    days = ((invite.valid_until.to_time - invite.created_at.to_time) / 1.day).round
    if days >= 300 then 'about a year (SC staff auto-join pattern)'
    elsif days.between?(29, 31) then 'about 30 days (IM default)'
    else 'other'
    end
  end

  def self.report(stats, lifetimes, per_tenant, config)
    say '=' * 76
    say "per tenant (#{per_tenant.size}):"
    per_tenant.sort_by { |_id, row| -row[:candidates] }.each do |tenant_id, row|
      say format('  tenant=%-26s candidates=%7d deleted=%7d', tenant_id, row[:candidates], row[:deleted])
    end
    say '-' * 76
    say 'candidates by requested lifetime:'
    lifetimes.sort_by { |_bucket, count| -count }.each { |bucket, count| say format('  %-46s %7d', bucket, count) }
    say '-' * 76
    %i[scanned kept_referenced_by_sc candidates selected over_limit deleted].each do |key|
      say format('  %-26s %7d', key, stats[key])
    end
    say '-' * 76
    if config[:apply]
      say "deleted #{stats[:deleted]} invite(s); backup: #{config[:backup_file]} (contains live tokens, delete it after verifying)"
    else
      say "dry run: would delete #{stats[:selected]} invite(s)"
    end
    say '=' * 76
  end

end
