module Actors

  class Tenant < Actor

    field :modules_selected, type: Array, default: []

    before_destroy :cache_expire!

    def cache_expire!
      ::User.where(:_id.in => self.descendants.mappings.distinct(:user_id)).cache_expire!
    end

    def self.modules_available
      @@modules_available ||= Dir.glob("config/apps/*/actor_defaults/*.yml").collect {|f| File.basename(f, File.extname(f)) }
    end

    def modules_available
      return [] unless app
      @modules_available ||= begin
        self.class.modules_available.select { |_mod| _mod.starts_with?("#{app.name}-") }
      end
    end

    def modules_selected
      (super & modules_available).compact.uniq
    end

    # ensures a uniq tenant name is determined
    def get_name
      @tenant_name ||= begin
        _criteria = self.class.where(parent_id: parent_id, :_id.ne => id)
        _criteria.name_uniq super
      end
    end

    def organization
      children.available.where(_type: Actors::Organization).first
    end

    def app
      @app ||= ancestors.where(_type: Actors::App).first
    end

    def access_control
      @access_control ||= AccessControl.for_tenant(id)
    end

    # returns group ids by Array of strings in the format of "group_name/name"
    def group_ids_named(names = [])
      access_control.select do |g|
        names.collect(&:underscore).include? "#{g.group_name.underscore}/#{g.name.underscore}"
      end.collect &:id
    end

    def users
      ::User.where(:actor_id.in => descendants.mappings.pluck(:map_actor_id))
    end

    def app_admins
      organization.descendants.where(name: 'app-admins').first
    end

    def tenant_admins
      organization.descendants.where(name: 'tenant-admins').first
    end

    def enterprises
      @enterprises ||= self.class.enterprises(self.id)
      @enterprises = nil unless @enterprises.any?
      @enterprises || []
    end

    def self.enterprises(tenant_ids)
      begin
        _enterprise_ids = Actors::Mapping.unscoped.available.where(:map_actor_id.in => ensure_bson(tenant_ids)).pluck(:parent_id)
        Actors::Enterprise.unscoped.available.where(:_id.in => _enterprise_ids).includes(:children).collect do |e|
          { 
            title: e.title,
            tenant_ids: e.children.unscoped.available.pluck(:map_actor_id).collect(&:to_s)
          }
        end
      end
    end

    def self.test
      find_by(_id: '5d2d7f3703948d068125ce69')
    end

    def self.cleanup_custom_groups!
      all.each &:cleanup_custom_groups!
    end

    def cleanup_custom_groups!
      Actor.logs! false
      unless self.organization.present?
        if self.deleted?
          self.destroy
          return
        end
        puts "NO ORGA FOR #{self.path}".red
        return
      end
      _to_migrate = self.children.groups_and_ous.where(:parent_ids.ne => self.organization.id)
      return _to_migrate
      _to_migrate.each do |old_actor|
        if old_actor.deleted || old_actor.children.empty?
          old_actor.destroy
        else
          puts "-" * 80
          puts "The Actor: #{old_actor.path} has #{old_actor.descendants.count} descendants!"
          # move to somewhere below organization maybe ?
          #old_actor.parent = self.organization
          #old_actor.save!
        end
      end
    end

    # Helper to migrate mappings from old groups into one or many new groups
    # old groups will be untouched and must be manually deleted
    # after verifying the migration was successful.
    def self.migrate_groups!(source_map={}, app_name: nil)
      # source_map = {
      #   old_group_name: %w(new_group_name),
      #   old_group_name2: %w(new_group_name2 new_group_name_extra),
      # }
      source_map = source_map.with_indifferent_access

      source_groups = Actors::App.named(app_name).first.container_tenants.descendants.groups.where(:name.in => source_map.keys)
      source_groups.each do |source_group|
        next if source_group.tenant.deleted?
        target_groups = source_group.tenant.organization.descendants.available.groups.where(:name.in => source_map.dig(source_group.name))
        puts "=" * 80
        puts "mappings from: #{source_group.path}"
        source_group.mappings.each do |mapping|
          target_groups.each do |target_group|
            puts " - mapping (#{mapping.map_actor.name}) into: #{target_group.path}"
            target_group.map_into! mapping.map_actor.user
          end
        end
      end
    end

  end

end
