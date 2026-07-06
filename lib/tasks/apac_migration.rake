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

  # Prints every write failure collected during the run (e.g. a unique-index
  # collision against a doc created natively on the target with a different
  # _id) and aborts — AFTER every copy step has already run, so a handful of
  # collisions never blocks the rest of the migration, but the run still ends
  # non-zero so it's never mistaken for a clean success.
  def apac_report_write_errors!(copier)
    return if copier.errors.empty?

    puts '-' * 80
    puts "WRITE ERRORS: #{copier.errors.size} doc(s) failed to write (target already has a" \
         ' different-_id doc at the same natural key — needs manual reconciliation):'
    copier.errors.each do |e|
      where = [e[:name], e[:path]].compact.join(' @ ')
      puts "  [#{e[:collection]}] _id=#{e[:id]} #{where}".rstrip
      puts "    #{e[:message]}"
    end
    abort "#{copier.errors.size} write error(s) — see above. Other collections were still copied."
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

  # App name -> target (APAC) absolute frontend URL. Fixed defaults for the two
  # known APAC frontends, so a plain `apac:copy` run (no extra ENV needed) always
  # points post-login/OAuth redirects at the right host — no step to forget.
  # TARGET_APP_URLS="name=url,..." overrides/extends these if ever needed
  # (e.g. a staging APAC frontend with a different host).
  def apac_default_target_app_urls
    { 'identity-management' => 'https://apac.ident.services', 'samedis-care' => 'https://apac.samedis.care' }
  end

  def apac_target_app_urls
    @apac_target_app_urls ||= apac_default_target_app_urls.merge(
      ENV['TARGET_APP_URLS'].to_s.split(',').filter_map do |pair|
        name, url = pair.split('=', 2)
        [name.to_s.strip, url.to_s.strip] if name.present? && url.present?
      end.to_h
    )
  end

  # Actors::App::Config#url is a literal DB value, not derived from ENV at
  # runtime (see User.host / User#redirect_url_authenticated) — copied verbatim
  # from EU it points post-login/OAuth redirects back at the EU frontend even
  # once the App document lives on the APAC cluster. Rewrite it per TARGET_APP_URLS;
  # apps with no mapping entry are left untouched (and reported, see apac:copy).
  def apac_app_url_rewrite
    lambda do |doc|
      target_url = apac_target_app_urls[doc['name']]
      next doc if target_url.blank?

      doc.merge('config' => (doc['config'] || {}).merge('url' => target_url))
    end
  end

  # `view_<app>_actors` (e.g. view_samedis_care_actors) is how SCB's read-only
  # user reads IM actor data — see Actors::App#create_app_view!. It's a MongoDB
  # VIEW (metadata in system.views), not a document collection, so the document
  # copy never brings it over — it must be (re)created explicitly on the target,
  # once per app (every App except identity-management, matching
  # Actors::App.apps_for_views). Idempotent: drops-if-exists then creates,
  # mirroring create_app_view! itself, just aimed at the target client instead
  # of Mongoid's default (source) connection.
  def apac_ensure_views!(copier)
    Actors::App.apps_for_views.each do |app|
      view_name = app.view_name
      command = {
        create: view_name,
        viewOn: 'actors',
        pipeline: [
          { '$match' => { 'deleted' => false } },
          { '$match' => { '$or' => [{ '_id' => app.id }, { 'parent_ids' => app.id }] } }
        ]
      }
      if copier.dry_run
        puts "  would (re)create view: #{view_name}"
        next
      end

      copier.target_client[view_name].drop
      copier.target_client.database.command(**command)
      puts "  (re)created view: #{view_name}"
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
    puts "  App URLs (target): #{apac_target_app_urls.map { |k, v| "#{k}->#{v}" }.join(', ')}"
    mapped_count = Actor.unscoped.where(:_id.in => resolver.app_actor_ids, :name.in => apac_target_app_urls.keys).count
    unmapped = resolver.app_actor_ids.count - mapped_count
    if unmapped.positive?
      puts "  WARN: #{unmapped} app(s) have no TARGET_APP_URLS entry — their config.url stays EU-valued."
    end
    puts apac_hr

    # 1. APAC tenant subtree (tenants + Organization/Ou/Group/Mapping)
    copier.copy(model: Actor, selector: resolver.subtree_actor_criteria.selector, label: 'actors (subtree)')
    # 1b. Structural ancestors (App + container/root nodes) so the tree, paths
    #     and roles/functionalities actors_app_id references resolve on target.
    copier.copy(model: Actor, selector: { '_id' => { '$in' => resolver.structural_ancestor_ids } },
                label: 'actors (ancestors)', deltaable: false)
    # 1c. All App definition nodes (incl. the identity-management base app).
    copier.copy(model: Actor, selector: { '_type' => 'Actors::App' },
                label: 'actors (apps)', deltaable: false, transform: apac_app_url_rewrite)
    # 1d. App-level skeleton (app "users"/app-admins groups, organization, OUs,
    #     containers) so app flows like ensure_app_membership! work on target.
    copier.copy(model: Actor, selector: { '_id' => { '$in' => resolver.app_skeleton_ids } },
                label: 'actors (app skeleton)', deltaable: false)
    # 1e. App-admin/tenant-admin grants (tenant_id: nil) — the actual rights
    #     behind login-as-admin. NOT the app's generic "users" membership group
    #     (excluded — would leak EU user actor ids for every registered user).
    copier.copy(model: Actor, selector: { '_id' => { '$in' => resolver.system_admin_mapping_ids } },
                label: 'actors (system admins)', deltaable: false)
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
    # 6. Migration tracking (mongoid_rails_migrations) — so the target treats all
    #    historical migrations as already run and does not replay them on boot.
    copier.copy(model: DataMigration, selector: {}, label: 'data_migrations', deltaable: false)
    # 7. (Re)create the view(s) SCB's read-only user reads actor data through —
    #    a MongoDB view is metadata, never brought over by the document copy.
    apac_ensure_views!(copier)

    puts '-' * 80
    if dry
      puts 'DRY_RUN: nothing written. Selection counts above.'
    else
      ApacMigration::LeakGuard.new(resolver).assert!(copier.target_client)
      puts "Leak guard passed. Total: #{copier.stats.sum { |_, v| v }} doc(s)."
      apac_report_write_errors!(copier)
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

  desc '(Re)create view_<app>_actors on the target — SCB reads IM actor data through it. [DRY_RUN]'
  task ensure_views: :environment do
    Actor.logs! false
    copier = ApacMigration::MongoCopier.new(dry_run: apac_dry_run?)
    apac_preflight!(copier)

    puts "apac:ensure_views (#{Rails.env})#{' [DRY_RUN]' if copier.dry_run}"
    puts apac_hr
    apac_ensure_views!(copier)
  end

  desc 'One-off fix: rewrite config.url on already-copied target Apps. Optional TARGET_APP_URLS override. [DRY_RUN]'
  task fix_app_urls: :environment do
    Actor.logs! false
    dry = apac_dry_run?
    url_map = apac_target_app_urls

    copier = ApacMigration::MongoCopier.new(dry_run: dry)
    apac_preflight!(copier)
    target = copier.target_client

    puts "apac:fix_app_urls (#{Rails.env})#{' [DRY_RUN]' if dry}"
    puts apac_hr

    url_map.each do |name, url|
      doc = target['actors'].find(_type: 'Actors::App', name: name).first
      if doc.nil?
        puts "  ! no target App named '#{name}' — skipped"
        next
      end

      current = doc.dig('config', 'url')
      if current == url
        puts "  = #{name}: already #{url}"
        next
      end

      if dry
        puts "  would update #{name}: #{current.inspect} -> #{url.inspect}"
      else
        target['actors'].update_one({ _id: doc['_id'] }, { '$set' => { 'config.url' => url } })
        puts "  updated #{name}: #{current.inspect} -> #{url.inspect}"
      end
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
      'actors (subtree)'      => [Actor, resolver.subtree_actor_criteria.selector],
      'actors (users)'        => [Actor, { '_id' => { '$in' => resolver.actor_user_ids } }],
      'actors (sys admins)'   => [Actor, { '_id' => { '$in' => resolver.system_admin_mapping_ids } }],
      'users'                 => [::User, { '_id' => { '$in' => resolver.user_ids } }],
      'invites'               => [Invite, resolver.invite_criteria.selector]
    }

    puts "apac:verify (#{Rails.env})"
    puts apac_hr
    # Completeness check: every SOURCE doc must exist on the target. Extra docs
    # on the target are native APAC records (e.g. live signups) — expected on a
    # live cluster, so they are reported but not a failure.
    complete = true
    checks.each do |label, (model, selector)|
      src_ids = model.collection.distinct('_id', selector)
      tgt_ids = target[model.collection.name.to_s].distinct('_id', selector)
      missing = src_ids - tgt_ids
      extra   = tgt_ids - src_ids
      complete &&= missing.empty?
      note = extra.any? ? "  (+#{extra.size} native on target)" : ''
      status = missing.empty? ? 'OK' : "MISSING #{missing.size}"
      puts "  #{label.ljust(18)} source=#{src_ids.size} target=#{tgt_ids.size} #{status}#{note}"
    end

    puts '-' * 80
    ApacMigration::LeakGuard.new(resolver).assert!(target)
    puts 'Leak guard passed.'
    abort 'Incomplete — some source docs are missing on the target (re-run apac:copy).' unless complete
    puts 'Verify OK (all source docs present on target).'
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
