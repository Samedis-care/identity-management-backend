# Repairs users who accepted a `tenant` invite while Invite#_process_accept_tenant had
# the inverted guard (introduced 2025-04-16 by 635b04f, fixed in #271). Those invites were
# marked `done: true` without ever mapping the user into the tenant's standard_user group,
# so `Staff#login_allowed` linked the account while the user got no access and no
# samedis-care-employee role. See Samedis-care/samedis-care-issues#2403
#
# Lives in db/migrate_manual, so it only runs when MANUAL is set:
#
#   # 1. report only, writes nothing, is NOT recorded as migrated (default)
#   MANUAL=true RAILS_ENV=live bundle exec rails db:migrate
#
#   # 2. apply, after reviewing the report
#   MANUAL=true APPLY=true RAILS_ENV=live bundle exec rails db:migrate
#
# Knobs: APPLY=true (write), LIMIT=n (cap repairs), TENANT_ID=<id> (single tenant),
#        SINCE=YYYY-MM-DD or SINCE=all (default floor: 2025-04-16, the day the bug shipped).
# Run once per cluster - the APAC cluster (RAILS_ENV=apac) has its own data.
#
# READ THIS BEFORE APPLYING
# ------------------------
# Actor#unmap_from! HARD-deletes the mapping (actor.rb:809), and Actor#before_save deletes
# any mapping flagged deleted (actor.rb:341). So a membership that somebody revoked on
# purpose leaves no trace and looks exactly like one this bug never created. This migration
# therefore CANNOT tell "broken by the bug" from "deliberately removed", and re-granting
# revoked access is the failure mode to worry about.
#
# Two guards narrow that risk, neither eliminates it:
#   * users who still hold any other live mapping below the tenant are skipped - they have
#     access already, and their missing standard_user mapping may well be intentional
#   * the report buckets by acceptance month, so the 2025-04 cliff is visible; anything
#     accepted before 2025-04 is almost certainly not this bug and worth inspecting
#
# The authoritative cross-check lives in the other database: samedis-care `Staff` records
# with `login_allowed: true` and no `left` date are the users who are supposed to have
# access. Reconcile the report against that list before running with APPLY=true.
class RepairMissingStandardUserMappings < Mongoid::Migration

  BUG_INTRODUCED = Time.utc(2025, 4, 16)

  # Anything accepted before BUG_INTRODUCED has some other cause and is not repaired:
  # the first live report found 68 of 94 predating the bug, going back to 2019, so this
  # state is long-standing and not a fingerprint of the inverted guard. SINCE=all lifts
  # the floor, SINCE=2024-01-01 moves it.
  def self.since_floor
    raw = ENV['SINCE'].to_s.strip
    return nil if raw.casecmp('all').zero?
    return BUG_INTRODUCED if raw.empty?

    Time.parse(raw).utc
  end

  def self.up
    apply = ENV['APPLY'].present?
    limit = ENV['LIMIT'].presence&.to_i
    only_tenant = ENV['TENANT_ID'].presence
    since = since_floor

    scope = Invite.where(invitable_type: 'tenant', done: true)
    scope = scope.where(tenant_id: only_tenant) if only_tenant

    stats = Hash.new(0)
    months = Hash.new(0)
    repaired = []

    say "scanning #{scope.count} accepted tenant invites (apply=#{apply})"

    scope.each do |invite|
      stats[:scanned] += 1
      say "  ... #{stats[:scanned]} scanned" if (stats[:scanned] % 500).zero?

      tenant = tenant_for(invite)
      if tenant.nil?
        stats[:skip_tenant_gone] += 1
        next
      end

      group = tenant.descendants.groups.available
                    .where(system: true, name: :standard_user).first
      if group.nil?
        # nothing to map into - the tenant itself needs repairing first
        stats[:skip_tenant_without_group] += 1
        next
      end

      user = invite.get_user
      if !user.is_a?(User) || user.deleted?
        stats[:skip_user_gone] += 1
        next
      end

      actor = user.actor
      if actor.nil? || actor.new_record?
        stats[:skip_user_without_actor] += 1
        next
      end

      if Actors::Mapping.where(parent: group, map_actor: actor).exists?
        stats[:already_mapped] += 1
        next
      end

      # guard: leave users alone who reach the tenant through some other group
      if Actors::Mapping.available
                        .where(map_actor_id: actor.id, :parent_ids.in => [tenant.id]).exists?
        stats[:skip_has_other_access] += 1
        next
      end

      bucket = invite.accepted_at&.strftime('%Y-%m') || 'unknown'
      months[bucket] += 1
      stats[:affected] += 1
      stats[:affected_before_bug] += 1 if invite.accepted_at && invite.accepted_at < BUG_INTRODUCED

      # counted as affected for the report, but out of repair scope
      if since && (invite.accepted_at.nil? || invite.accepted_at < since)
        stats[:skip_before_since] += 1
        next
      end

      stats[:in_repair_scope] += 1

      if limit && repaired.size >= limit
        stats[:over_limit] += 1
        next
      end

      unless apply
        repaired << invite.id
        next
      end

      begin
        group.map_into!(actor)
        repaired << invite.id
        stats[:repaired] += 1
      rescue StandardError => e
        stats[:failed] += 1
        say "  FAILED invite=#{invite.id} tenant=#{tenant.id} user=#{user.email}: " \
            "#{e.class}: #{e.message}"
      end
    end

    report(stats, months, apply, since)

    # keep the migration unrecorded so the real run still has something to do
    unless apply
      raise 'DRY RUN: nothing written and migration deliberately not recorded. ' \
            'Re-run with APPLY=true once the report has been reconciled against the ' \
            'samedis-care Staff#login_allowed list.'
    end
  end

  # Reversing would delete mappings, and because revoked mappings are hard-deleted there
  # is no way to tell the ones this migration created from ones that already existed or
  # were legitimately added afterwards. Removing the wrong one silently drops a user's
  # access, so this is not reversible.
  def self.down
    raise Mongoid::IrreversibleMigration,
          'Cannot safely remove standard_user mappings - see the comment in this file. ' \
          'To revoke a single user use group.unmap_from!(user.actor) explicitly.'
  end

  def self.tenant_for(invite)
    return nil if invite.tenant_id.blank?

    oid = BSON::ObjectId.from_string(invite.tenant_id.to_s) rescue nil
    return nil if oid.nil?

    Actors::Tenant.available.where(_id: oid).first
  end

  def self.report(stats, months, apply, since = nil)
    say '=' * 76
    say "accepted tenant invites with no standard_user mapping, by acceptance month"
    say "(the inverted guard shipped with 635b04f on #{BUG_INTRODUCED.strftime('%Y-%m-%d')})"
    months.keys.sort.each do |month|
      say format('  %-8s %5d %s', month, months[month], '#' * [months[month], 50].min)
    end
    say '-' * 76
    %i[scanned affected affected_before_bug skip_before_since in_repair_scope
       repaired failed already_mapped skip_has_other_access
       skip_tenant_without_group skip_tenant_gone skip_user_gone
       skip_user_without_actor over_limit].each do |key|
      say format('  %-26s %6d', key, stats[key])
    end
    say '-' * 76
    say(if since
          "repair scope: accepted on/after #{since.strftime('%Y-%m-%d')} " \
            "(#{stats[:in_repair_scope]} of #{stats[:affected]} affected). " \
            'SINCE=all lifts the floor, SINCE=YYYY-MM-DD moves it.'
        else
          "repair scope: NO date floor, all #{stats[:affected]} affected rows in scope"
        end)
    say '=' * 76
    say(apply ? "repaired #{stats[:repaired]} mapping(s)" : 'DRY RUN - nothing written')
  end

end
