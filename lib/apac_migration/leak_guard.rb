module ApacMigration
  # Post-copy assertion: proves no EU tenant data landed on the APAC cluster.
  # Runs against the TARGET cluster after every copy phase. Raises on the first
  # violation so a leaking run fails loudly instead of completing silently.
  class LeakGuard
    def initialize(resolver)
      @resolver = resolver
    end

    def assert!(target_client)
      # Blacklist of EU tenants that exist in the SOURCE. Anything on the target
      # tied to one of these is a genuine leak; records created natively on the
      # (live) APAC cluster are not in this set and are correctly ignored.
      eu = @resolver.eu_tenant_ids
      # Invite#tenant_id is `type: Object`, stored as a mix of String and
      # BSON::ObjectId — match both. Mapping#tenant_id is a clean ObjectId.
      eu_mixed = eu + eu.map(&:to_s)
      errors = []

      # 1. No Mapping on the target may point at an EU source tenant.
      bad_map = target_client['actors'].find(
        '_type' => 'Actors::Mapping',
        'tenant_id' => { '$in' => eu }
      ).first
      errors << "actors: Mapping #{bad_map['_id']} points at EU tenant #{bad_map['tenant_id']}" if bad_map

      # 2. No EU source Tenant may exist on the target.
      bad_tenant = target_client['actors'].find(
        '_type' => 'Actors::Tenant',
        '_id' => { '$in' => eu }
      ).first
      errors << "actors: EU Tenant #{bad_tenant['_id']} present on target" if bad_tenant

      # 3. No Invite on the target may belong to an EU source tenant.
      bad_inv = target_client['invites'].find('tenant_id' => { '$in' => eu_mixed }).first
      errors << "invites: #{bad_inv['_id']} belongs to EU tenant #{bad_inv['tenant_id']}" if bad_inv

      # 4. No user on the target may reference an EU tenant in its cached set.
      bad_user = target_client['users'].find('tenants_cached' => { '$in' => eu_mixed }).first
      errors << "users: #{bad_user['_id']} caches EU tenant(s)" if bad_user

      return true if errors.empty?

      raise "APAC LEAK GUARD FAILED:\n - #{errors.join("\n - ")}"
    end
  end
end
