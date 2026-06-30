require_relative '../apac_migration/collection_registry'
require_relative '../apac_migration/tenant_set_resolver'
require_relative '../apac_migration/mongo_copier'
require_relative '../apac_migration/leak_guard'
require_relative '../apac_migration/s3_copier'

# APAC region split (issue #2336). Marks tenants and copies the APAC slice of
# the identity data onto the separate APAC IMB cluster.
#
# Order of operations (see docs/apac_migration.md):
#   1. SCB marks region='apac' and exports Tenant.apac.pluck(:_id)
#   2. IMB: apac:mark_region with that id list
#   3. IMB: apac:copy (warm) -> apac:report_dangling -> apac:verify
#   4. window: apac:copy UPDATED_SINCE=... -> apac:verify
#
# Conventions: DRY_RUN=true, LIMIT, THREADS, BATCH_SIZE.
# Target cluster access is ONLY via runtime ENV TARGET_MONGODB_URI.
namespace :apac do
  # --- shared helpers -------------------------------------------------------

  def apac_hr
    '=' * 80
  end

  def apac_dry_run?
    ENV['DRY_RUN'].to_s == 'true'
  end

  def apac_tenant_ids_from_env
    if ENV['TENANT_IDS'].present?
      ENV['TENANT_IDS'].split(/[\s,]+/).reject(&:blank?)
    elsif ENV['TENANT_IDS_FILE'].present?
      file = ENV['TENANT_IDS_FILE']
      abort "TENANT_IDS_FILE not found: #{file}" unless File.exist?(file)
      File.readlines(file).map(&:strip).reject(&:blank?)
    end
  end

  def apac_resolver
    ApacMigration::TenantSetResolver.new(tenant_ids: apac_tenant_ids_from_env)
  end

  # Shows source + target clusters and pings the target before any write.
  # In dry-run the target is shown (parsed from ENV) but not contacted.
  def apac_preflight!(copier, s3: false)
    src = copier.connection_info(copier.source_client)
    puts apac_hr
    puts 'PREFLIGHT — Verbindungs-Check'
    puts "  SOURCE (read)   db=#{src[:database]}"
    puts "                  hosts=#{src[:hosts].join(', ')}"

    if copier.dry_run
      tgt = copier.target_summary
      puts "  TARGET (write)  db=#{tgt[:database]}"
      puts "                  hosts=#{tgt[:hosts].join(', ')}"
      puts '                  (dry-run — target NOT contacted, no write)'
    else
      print '  TARGET (write)  pinging… '
      copier.ping_target!
      tgt = copier.connection_info(copier.target_client)
      puts 'OK'
      puts "                  db=#{tgt[:database]}"
      puts "                  hosts=#{tgt[:hosts].join(', ')}"
      if copier.target_is_source?
        abort 'ABORT: TARGET equals SOURCE (same hosts + database). Refusing to copy onto the source.'
      end
    end

    # IMB forces the target database (TARGET_DATABASE). Writing app data into a
    # system DB is always a mistake — only reachable by overriding
    # TARGET_MONGODB_DATABASE to a system name. Abort defensively.
    if %w[admin local config].include?(tgt[:database].to_s)
      abort "ABORT: TARGET database is '#{tgt[:database]}' (a system database). " \
            'Unset/correct TARGET_MONGODB_DATABASE — IMB defaults to identity_management_apac.'
    end

    if s3
      puts "  S3              source bucket=#{ENV['AWS_S3_BUCKET'].presence || '(unset)'}"
      puts "                  target bucket=#{ENV['TARGET_S3_BUCKET'].presence || '(unset)'}"
    end
    puts apac_hr
  end

  # Clears EU tenant cache fields on user docs before they are written to APAC.
  def apac_user_cache_clear
    lambda do |doc|
      doc.merge(
        'tenant_candos_cached'    => nil,
        'tenant_candos_cached_at' => nil,
        'tenants_cached'          => nil,
        'tenants_cached_at'       => nil,
        'tenant_access_group_ids' => nil
      )
    end
  end

  # --- tasks ----------------------------------------------------------------

  desc 'Mark tenants as APAC region. TENANT_IDS="id1,id2" or TENANT_IDS_FILE=path [DRY_RUN=true]'
  task mark_region: :environment do
    Actor.logs! false
    dry = apac_dry_run?
    ids = apac_tenant_ids_from_env
    abort 'Provide TENANT_IDS="id1,id2,..." or TENANT_IDS_FILE=path/to/ids.txt' if ids.blank?

    puts apac_hr
    puts "apac:mark_region (#{Rails.env})#{' [DRY_RUN]' if dry} — #{ids.size} id(s)"
    puts apac_hr

    stats = Hash.new(0)
    ids.each do |raw|
      oid = BSON::ObjectId(raw) rescue nil
      if oid.nil?
        puts "  ! invalid id: #{raw}"
        stats[:invalid] += 1
        next
      end

      tenant = Actors::Tenant.where(_id: oid).first
      if tenant.nil?
        puts "  ! not found / not a tenant: #{raw}"
        stats[:missing] += 1
        next
      end

      if tenant.region == 'apac'
        stats[:already] += 1
        next
      end

      if dry
        puts "  would set apac: #{raw} (#{tenant.name})"
      else
        tenant.set(region: 'apac') # atomic $set, no callbacks/validations
        puts "  set apac:       #{raw} (#{tenant.name})"
      end
      stats[:updated] += 1
    end

    puts '-' * 80
    puts "updated=#{stats[:updated]} already_apac=#{stats[:already]} " \
         "missing=#{stats[:missing]} invalid=#{stats[:invalid]}"
  end

  desc 'Copy the APAC identity slice to TARGET_MONGODB_URI [DRY_RUN][LIMIT][UPDATED_SINCE][THREADS][BATCH_SIZE]'
  task copy: :environment do
    Rails.application.eager_load! # so CollectionRegistry sees all models
    Actor.logs! false
    dry           = apac_dry_run?
    limit         = ENV['LIMIT'].presence&.to_i
    updated_since = ENV['UPDATED_SINCE'].present? ? Time.zone.parse(ENV['UPDATED_SINCE']) : nil

    ApacMigration::CollectionRegistry.assert_complete!

    resolver = apac_resolver
    if resolver.apac_tenant_ids.empty?
      abort 'No APAC tenants (set region=apac via apac:mark_region, or pass TENANT_IDS).'
    end

    copier = ApacMigration::MongoCopier.new(dry_run: dry, limit:, updated_since:)
    apac_preflight!(copier)

    puts "apac:copy (#{Rails.env})#{' [DRY_RUN]' if dry} — #{resolver.apac_tenant_ids.size} tenant(s)"
    puts "  updated_since=#{updated_since || '(full)'} limit=#{limit || '(none)'}"
    puts "  threads=#{copier.threads} batch=#{copier.batch_size}"
    puts apac_hr

    # 1. APAC tenant subtree (tenants + Organization/Ou/Group/Mapping)
    copier.copy(model: Actor, selector: resolver.subtree_actor_criteria.selector, label: 'actors (subtree)')
    # 1b. Structural ancestors (App + container/root nodes) so the tree, paths
    #     and roles/functionalities actors_app_id references resolve on target.
    copier.copy(model: Actor, selector: { '_id' => { '$in' => resolver.structural_ancestor_ids } },
                label: 'actors (ancestors)', deltaable: false)
    # 1c. All App definition nodes (incl. the identity-management base app).
    copier.copy(model: Actor, selector: { '_type' => 'Actors::App' },
                label: 'actors (apps)', deltaable: false)
    # 2. Personal Actors::User nodes of migrated users (live in user_container)
    copier.copy(model: Actor, selector: { '_id' => { '$in' => resolver.actor_user_ids } }, label: 'actors (user nodes)')
    # 3. User identities — EU cache fields stripped on copy
    copier.copy(model: ::User, selector: { '_id' => { '$in' => resolver.user_ids } }, label: 'users', 
                transform: apac_user_cache_clear)
    # 4. Invites scoped to APAC tenants
    copier.copy(model: Invite, selector: resolver.invite_criteria.selector, label: 'invites')
    # 5. Global reference data (no identity data) — copied whole so role_ids match
    copier.copy(model: Role,          selector: {}, label: 'roles',           deltaable: false)
    copier.copy(model: Functionality, selector: {}, label: 'functionalities', deltaable: false)
    copier.copy(model: Content,       selector: {}, label: 'contents',        deltaable: false)

    puts '-' * 80
    if dry
      puts 'DRY_RUN: nothing written. Selection counts above.'
    else
      ApacMigration::LeakGuard.new(resolver).assert!(copier.target_client)
      puts "Leak guard passed. Total: #{copier.stats.sum { |_, v| v }} doc(s)."
    end
  end

  desc 'Copy Shrine S3 objects (tenant images + user avatars) of the APAC set to TARGET_S3_* [DRY_RUN][THREADS]'
  task copy_s3: :environment do
    Actor.logs! false
    dry      = apac_dry_run?
    threads  = Integer(ENV.fetch('THREADS', 4))
    resolver = apac_resolver
    if resolver.apac_tenant_ids.empty?
      abort 'No APAC tenants (set region=apac via apac:mark_region, or pass TENANT_IDS).'
    end

    s3 = ApacMigration::S3Copier.new(dry_run: dry, threads:)
    buckets = s3.buckets_summary

    puts apac_hr
    puts 'PREFLIGHT — S3'
    puts "  SOURCE bucket=#{buckets[:source]}"
    puts "  TARGET bucket=#{buckets[:target]}"
    if dry
      puts '                (dry-run — target NOT contacted)'
    else
      print '  TARGET access… '
      begin
        s3.ping_target!
        puts "OK (region=#{s3.target_region})"
      rescue Aws::S3::Errors::Forbidden, Aws::S3::Errors::AccessDenied
        puts "WARN: HeadBucket forbidden (region=#{s3.target_region}). " \
             'Target creds likely lack s3:ListBucket — continuing; PutObject will be attempted per object.'
      end
    end
    puts apac_hr
    puts "apac:copy_s3 (#{Rails.env})#{' [DRY_RUN]' if dry} — #{resolver.apac_tenant_ids.size} tenant(s)"

    # Collect every S3 key referenced by the migrated documents' image_data.
    # Keys come ONLY from migrated docs, so EU objects can never be touched.
    print "  scanning migrated docs for images…\r"
    $stdout.flush
    keys = []
    with_images = ->(criteria) { criteria.where(:image_data.exists => true).where(:image_data.ne => nil) }

    # Every actor the mongo copy writes can carry an image (tenant subtree,
    # structural ancestors, ALL App nodes incl. their logos, and user nodes).
    copied_actor_ids = (resolver.structural_ancestor_ids +
                        resolver.app_actor_ids +
                        resolver.actor_user_ids).uniq

    with_images.call(resolver.subtree_actor_criteria).each do |actor|
      keys.concat(ApacMigration::S3Copier.keys_from(actor.image_data))
    end
    with_images.call(Actor.unscoped.where(:_id.in => copied_actor_ids)).each do |actor|
      keys.concat(ApacMigration::S3Copier.keys_from(actor.image_data))
    end
    with_images.call(::User.unscoped.where(:_id.in => resolver.user_ids)).each do |user|
      keys.concat(ApacMigration::S3Copier.keys_from(user.image_data))
    end
    keys.uniq!

    puts "  #{keys.size} S3 object key(s) referenced by the migrated set"

    s3.copy_keys(keys)

    puts '-' * 80
    if dry
      puts "DRY_RUN: would copy up to #{s3.stats[:would_copy]} object(s) (existing ones skipped on a real run)."
    else
      puts "copied=#{s3.stats[:copied]} skipped_existing=#{s3.stats[:skipped]} " \
           "missing_source=#{s3.stats[:missing_source]}"
    end
  end

  desc 'Verify source vs target counts + leak guard (requires TARGET_MONGODB_URI)'
  task verify: :environment do
    Actor.logs! false
    resolver = apac_resolver
    abort 'No APAC tenants to verify.' if resolver.apac_tenant_ids.empty?

    copier = ApacMigration::MongoCopier.new
    apac_preflight!(copier)
    target = copier.target_client

    checks = {
      'actors (subtree)' => [Actor, resolver.subtree_actor_criteria.selector],
      'actors (users)'   => [Actor, { '_id' => { '$in' => resolver.actor_user_ids } }],
      'users'            => [::User, { '_id' => { '$in' => resolver.user_ids } }],
      'invites'          => [Invite, resolver.invite_criteria.selector]
    }

    puts "apac:verify (#{Rails.env})"
    puts apac_hr
    ok = true
    checks.each do |label, (model, selector)|
      src = model.collection.find(selector).count
      tgt = target[model.collection.name.to_s].count_documents(selector)
      match = src == tgt
      ok &&= match
      puts "  #{label.ljust(20)} source=#{src}  target=#{tgt}  #{match ? 'OK' : 'MISMATCH'}"
    end

    puts '-' * 80
    ApacMigration::LeakGuard.new(resolver).assert!(target)
    puts 'Leak guard passed.'
    abort 'Count mismatch — see above.' unless ok
    puts 'Verify OK.'
  end

  desc 'Report cross-region dangling refs (does not copy them)'
  task report_dangling: :environment do
    Actor.logs! false
    resolver = apac_resolver
    migrated_users = resolver.user_ids.to_set

    puts apac_hr
    puts "apac:report_dangling (#{Rails.env})"
    puts apac_hr

    # Migrated users whose supervisor/stand-in points at a non-migrated (EU) user.
    count = 0
    ::User.unscoped.where(:_id.in => resolver.user_ids).each do |user|
      %i[supervisor_actor_id stand_in_actor_id].each do |ref|
        actor_id = user.send(ref)
        next if actor_id.blank?

        ref_user_id = Actor.unscoped.where(_id: actor_id).first&.user_id
        next if ref_user_id.blank? || migrated_users.include?(ref_user_id)

        puts "  user #{user.id} (#{user.email}) #{ref} -> EU user #{ref_user_id}"
        count += 1
      end
    end

    # Enterprises that group APAC together with EU tenants.
    Actors::Tenant.apac.each do |tenant|
      tenant.enterprises.each do |ent|
        eu = ent[:tenant_ids].map { |id| BSON::ObjectId(id) } - resolver.apac_tenant_ids
        next if eu.empty?

        puts "  enterprise '#{ent[:title]}' spans regions; EU tenant(s): #{eu.map(&:to_s).join(', ')}"
        count += 1
      end
    end

    puts '-' * 80
    puts "#{count} cross-region ref(s) reported. These are NOT copied."
  end
end
