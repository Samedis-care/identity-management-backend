module ApacMigration
  # Post-copy assertion: proves no EU tenant data landed on the APAC cluster.
  # Runs against the TARGET cluster after every copy phase. Raises on the first
  # violation so a leaking run fails loudly instead of completing silently.
  class LeakGuard
    def initialize(resolver)
      @resolver = resolver
    end

    def assert!(target_client)
      apac = @resolver.apac_tenant_ids
      # Invite#tenant_id is `type: Object` and stored as a mix of String and
      # BSON::ObjectId, so match both representations (Mapping#tenant_id is a
      # clean ObjectId and only needs `apac`).
      apac_mixed = apac + apac.map(&:to_s)
      errors = []

      # 1. Every Mapping on the target must point at an APAC tenant.
      bad_map = target_client['actors'].find(
        '_type' => 'Actors::Mapping',
        'tenant_id' => { '$nin' => apac }
      ).first
      errors << "actors: Mapping #{bad_map['_id']} has non-APAC tenant_id #{bad_map['tenant_id']}" if bad_map

      # 1b. Every Tenant actor on the target must be in the APAC set (guards the
      #     structural-ancestor copy from ever pulling in a sibling tenant).
      bad_tenant = target_client['actors'].find(
        '_type' => 'Actors::Tenant',
        '_id' => { '$nin' => apac }
      ).first
      errors << "actors: Tenant #{bad_tenant['_id']} is not in the APAC set" if bad_tenant

      # 2. Every Invite on the target must belong to an APAC tenant.
      bad_inv = target_client['invites'].find('tenant_id' => { '$nin' => apac_mixed }).first
      errors << "invites: #{bad_inv['_id']} has non-APAC tenant_id #{bad_inv['tenant_id']}" if bad_inv

      # 3. No migrated user may retain EU cache fields (tenant ids/candos).
      bad_user = target_client['users'].find(
        '$or' => [
          { 'tenants_cached' => { '$nin' => [nil, []] } },
          { 'tenant_candos_cached' => { '$ne' => nil } },
          { 'tenant_access_group_ids' => { '$nin' => [nil, {}] } }
        ]
      ).first
      errors << "users: #{bad_user['_id']} still has EU cache fields populated" if bad_user

      return true if errors.empty?

      raise "APAC LEAK GUARD FAILED:\n - #{errors.join("\n - ")}"
    end
  end
end
