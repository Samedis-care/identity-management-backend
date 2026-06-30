module ApacMigration
  # Safety core. Every collection that holds tenant-scoped data must be
  # explicitly classified as either COPIED or EXCLUDED. A newly introduced
  # tenant-scoped model that is neither makes `assert_complete!` raise — so a
  # future model can be neither silently leaked onto the APAC cluster nor
  # silently forgotten during the copy.
  module CollectionRegistry
    module_function

    # Collections copied to the APAC cluster, with how they are selected.
    COPIED = {
      'actors'          => 'APAC tenant subtree (parent_ids ∈ apac) + migrated Actors::User nodes',
      'users'           => 'identities with ≥1 APAC mapping; EU cache fields cleared on copy',
      'invites'         => 'tenant_id ∈ apac',
      'roles'           => 'global app reference data (no identity data); copied so role_ids match',
      'functionalities' => 'global app reference data (no identity data)',
      'contents'        => 'global app reference data (no identity data)'
    }.freeze

    # Tenant-scoped or identity-adjacent collections deliberately NOT copied.
    EXCLUDED = {
      'account_activities' => 'audit log, regenerates; would carry EU login/IP data',
      'downloads'          => 'transient export artifacts',
      'suppression_lists'  => 'global EU mail suppression',
      'email_blacklists'   => 'global EU mail blacklist'
    }.freeze

    # Models that carry an explicit tenant_id field — these MUST all be
    # classified, because they are the ones that can leak cross-region data.
    def tenant_scoped_collections
      scoped = ApplicationDocument.descendants.select do |klass|
        klass.respond_to?(:fields) && klass.fields.key?('tenant_id')
      end
      scoped.map { |klass| klass.collection.name.to_s }.uniq
    end

    def assert_complete!
      classified = COPIED.keys + EXCLUDED.keys
      unreviewed = tenant_scoped_collections - classified
      return true if unreviewed.empty?

      raise <<~MSG
        ApacMigration::CollectionRegistry: unreviewed tenant-scoped collection(s): #{unreviewed.join(', ')}.
        Add each to COPIED (with a safe selector) or EXCLUDED in
        lib/apac_migration/collection_registry.rb before running the migration.
      MSG
    end
  end
end
