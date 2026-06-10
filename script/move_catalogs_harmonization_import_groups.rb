# Migrates Actors::Group "catalogs_harmonization_import" from its previous parent
# (samedis_care_manage Ou) to the samedis_care_device Ou inside the same tenant.
#
# Background: the group was originally placed under "Administration" in the
# samedis-care actor_defaults. It now lives under "Devices". For tenants that
# were already provisioned with the old layout, this script reparents the
# existing group; ensure_defaults! is additive and would otherwise create a
# second group at the new location.
#
# IMPORTANT: Actor#path is sticky — ensure_required_fields uses `path ||=
# determine_path`, so simply changing `parent` does NOT refresh the stored
# path. This script therefore clears path and the memoization variables
# before saving, so the path is recomputed from the new parent.
#
# Usage in Rails console:
#
#   # Dry run (no writes):
#   ENV['DRY_RUN'] = '1'
#   load Rails.root.join('script/move_catalogs_harmonization_import_groups.rb').to_s
#
#   # Apply:
#   ENV.delete('DRY_RUN')
#   load Rails.root.join('script/move_catalogs_harmonization_import_groups.rb').to_s
#
# Or as a one-liner from the shell:
#   DRY_RUN=1 bin/rails runner script/move_catalogs_harmonization_import_groups.rb
#   bin/rails runner script/move_catalogs_harmonization_import_groups.rb

GROUP_NAME       = 'catalogs_harmonization_import'.freeze
TARGET_OU_NAME   = 'samedis_care_device'.freeze
APP_NAME         = 'samedis-care'.freeze
DRY_RUN          = ENV['DRY_RUN'].to_s == '1'

stats = { found: 0, moved: 0, already_correct: 0, no_target_ou: 0,
          no_tenant: 0, duplicate_at_target: 0, errors: 0 }

groups = Actors::Group.where(name: GROUP_NAME)
puts "Found #{groups.count} group(s) named #{GROUP_NAME.inspect}#{' (DRY RUN)' if DRY_RUN}"

groups.each do |group|
  stats[:found] += 1
  tenant = group.tenant

  # Skip groups that don't sit under a Tenant (e.g. template/defaults trees).
  unless tenant
    puts "  SKIP #{group.id} #{group.path} — no tenant ancestor"
    stats[:no_tenant] += 1
    next
  end

  # Only touch samedis-care tenants.
  unless tenant.app&.name == APP_NAME
    puts "  SKIP #{group.id} #{group.path} — tenant app=#{tenant.app&.name.inspect}"
    next
  end

  target_ou = Actors::Ou.where(name: TARGET_OU_NAME, :parent_ids.in => [tenant.id]).first
  unless target_ou
    puts "  WARN #{group.id} #{group.path} — no #{TARGET_OU_NAME} Ou under tenant #{tenant.name}"
    stats[:no_target_ou] += 1
    next
  end

  correct_path = "#{target_ou.path} / #{group.name}"

  if group.parent_id == target_ou.id && group.path == correct_path
    puts "  OK   #{group.id} #{group.path} — already under #{TARGET_OU_NAME} with correct path"
    stats[:already_correct] += 1
    next
  end

  # If a DIFFERENT undeleted group with the same name already sits at the
  # target Ou (e.g. a fresh ensure_defaults! run already created one), do
  # NOT silently merge — surface it for manual review.
  existing_at_target = Actors::Group.where(
    name: GROUP_NAME,
    parent_id: target_ou.id,
    deleted: false,
    :_id.ne => group.id
  ).first
  if existing_at_target
    puts "  CONFLICT #{group.id} #{group.path} — duplicate at target: #{existing_at_target.id} #{existing_at_target.path}"
    stats[:duplicate_at_target] += 1
    next
  end

  old_path = group.path
  begin
    if DRY_RUN
      puts "  WOULD MOVE #{group.id} from #{group.parent&.path.inspect} to #{target_ou.path.inspect}"
      puts "             path #{old_path.inspect} -> #{correct_path.inspect}" if old_path != correct_path
    else
      # Reparent (Mongoid::Tree updates parent_id + parent_ids).
      group.parent = target_ou
      # Force path to be recomputed from the new parent. The default
      # ensure_required_fields uses `path ||= determine_path`, so we must
      # clear both the field and the memoization variables.
      group.path = nil
      group.instance_variable_set(:@determine_path, nil)
      group.instance_variable_set(:@ensure_required_fields, nil)
      group.save!
      group.reload
      puts "  MOVED #{group.id} #{old_path} -> #{group.path}"
    end
    stats[:moved] += 1
  rescue => e
    puts "  ERROR #{group.id} #{old_path}: #{e.class}: #{e.message}"
    stats[:errors] += 1
  end
end

puts "---"
puts "Summary: #{stats.inspect}"
puts "DRY RUN — no changes written. Re-run without DRY_RUN=1 to apply." if DRY_RUN
