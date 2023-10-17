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
Dir.glob('config/apps/*').collect { |d| File.basename(d) }.each do |app_name|
  puts "ensuring app: #{app_name} ..."
  apps[app_name] = Actors::App.available.named(app_name).first_or_create(
    system: true,
    short_name: app_name,
    parent: Actors::App.app_container,
    config: {
      locales: %w(de-DE en-US fr-FR nl-NL ru-KG)
    }
  )
  puts "- ensuring defaults for: #{apps[app_name].name} ..."
  apps[app_name].save
end
puts '=' * 80
puts 'Apps ensured!'
puts '=' * 80

# Insert Candos, Roles and locales for these apps
Actors::App.seed!
Actors::App.each(&:ensure_defaults!)

Dir.glob('config/apps/*').each do |app_dir|
  app_name = File.basename(app_dir)
  app = apps[app_name]
  tenant_ymls = Dir.glob("config/apps/#{app_name}/tenants/*.yml")
  tenant_ymls.each do |filename|
    attrs = YAML.load_file(filename).with_indifferent_access
    tenant = begin
      if BSON::ObjectId.legal?(attrs[:id])
        Actors::Tenant.where(
          parent: app.container_tenants,
          id: BSON::ObjectId(attrs[:id])
        ).first_or_create(attrs.except(:id).merge(system: true))
      else
        Actors::Tenant.where(
          parent: app.container_tenants,
          name: attrs[:name]
        ).first_or_create(attrs.except(:name).merge(system: true))
      end
    rescue StandardError => e
      raise e
    end
    puts "ensuring tenant #{tenant.name} in #{app_name}"
    tenant.save
    tenant.ensure_defaults!
    tenant.descendants.groups.each do |g|
      g.map_into! Actors::User.global_admin
    end
  end
end

apps.each do |name, app|
  admin_group = app.children.find_by(name: 'app-admins')
  admin_group.map_into! Actors::User.global_admin
end

# default Tenant
puts '=' * 80
puts 'Default IM Admin ensured!'
puts '=' * 80

# Import/Update email domain blacklist
EmailBlacklist.import_list('config/email_blacklist.txt')

Actor.system_override = false

# Expire cached tenants and candos
User.cache_expire!

# re-populate access control cache in a single db aggregation with merge
Actors::Mapping.merge_tenant_access_group_ids!
