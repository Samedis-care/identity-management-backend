# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

# only run anything if called via `rails db:seed manual=1`
unless ENV.key?('manual')
  puts "="* 80
  puts "SKIPPING seeds because manual flag not passed"
  puts "="* 80
  exit
end

Actor.logs! false

# Set up default structure

# Container where all users reside in
Actor.user_container.set(system: true)
Actor.user_container.set(short_name: :users)
# Container where all apps reside in
Actor.app_container.set(system: true)
Actor.app_container.set(short_name: :apps)

# Flush actor & tenant cache for users
User.cache_expire!

# Create Admin account
Actors::User.ensure_global_admin!
puts "=" * 80
puts "Admin Account ensured!"
puts "=" * 80

# cleanup (for seeds on updates)
Actors::User.cleanup_orphans!
Actors::Mapping.cleanup_orphans!

## Set up apps
apps = {}
%w(identity-management).each do |app_name|
  apps[app_name] = Actors::App.available.named(app_name).first_or_create(
    system: true,
    short_name: app_name,
    parent: Actors::App.app_container
  )
  apps[app_name].ensure_defaults!
end
app_im = apps['identity-management']
puts "=" * 80
puts "Apps ensured!"
puts "=" * 80


# ensure default admin tenant with the default admin user as member
admin_tenant = app_im.container_tenants.children.where(name: 'system').first_or_create(
  short_name: 'System',
  full_name: 'System',
  title: 'System',
  system: true
)
admin_tenant.save if admin_tenant.changes.any?
admin_tenant.ensure_defaults!
admin_group = app_im.children.find_by(name: 'app-admins')
admin_group.map_into! Actors::User.global_admin
# default Tenant
puts "=" * 80
puts "Default IM Admin ensured!"
puts "=" * 80

# Insert Candos, Roles and locales for these apps
Actors::App.seed!

# Import/Update email domain blacklist
EmailBlacklist.import_list('config/email_blacklist.txt')

Actor.system_override = false

# Expire cached tenants and candos
User.cache_expire!

# re-populate access control cache in a single db aggregation with merge
Actors::Mapping.merge_tenant_access_group_ids!
