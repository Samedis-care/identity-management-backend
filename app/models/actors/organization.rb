module Actors

  class Organization < Actor

    def insertable_child_types
      %i[ou group]
    end

    # determine dynamic organization defaults
    # if this is a tenant's orga
    def defaults
      @defaults = nil if @defaults.blank?
      @defaults ||= begin
        _defaults = begin
          if app.present? && (parent.is_a?(Tenant) || parent.is_a?(App))
            #app.organization.get_tree.slice(:children)
            { children: self.get_app_orga }
          else
            {}
          end
        end
        _modules_selected = self.parent.try(:modules_selected)
        # mixin selected module orga
        # which can hold extra children in a .yml file
        # under "config/apps/app_name/actor_defaults/app_name.yml"
        if parent.is_a?(Tenant) && _modules_selected.try(:any?)
          _modules_selected.each do |_mod|
            _module_file = "#{Rails.root}/#{Actors::App.app_actor_defaults_path(app.name)}/#{_mod}.yml"
            if File.exist?(_module_file)
              _selected = YAML.load_file(_module_file).dig(app.name).with_indifferent_access
              _defaults[:children] = _defaults[:children] + _selected[:children] if _selected[:children].any?
            end
          end
        end
        _defaults
      end
    end

    def app_defaults_import!
      raise "WRONG NODE! MUST BE ORGANIZATION BELOW AN APP" unless parent.is_a?(Actors::App)
      return unless File.exist?(app.app_actor_defaults_filepath)
      _import_defaults = YAML.load_file("#{Rails.root}/#{app.app_actor_defaults_filepath}").dig(app.name).with_indifferent_access
      if _import_defaults.dig(:children).any?
        self.ensure_defaults!(with_defaults: _import_defaults)
      else
        debug_puts "no defaults to import!"
      end
    end

    def app_defaults_dump!
      app = ancestors.find_by(_type: App)
      FileUtils.mkdir_p(app.class.app_actor_defaults_path(app.name))
      _yaml = { 
        # app.name => app.organization.get_tree(without: [:template_actor_id]).slice(:children)
        app.name => { children: self.get_app_orga(without: [:template_actor_id]) }
      }.to_h.deep_stringify_keys.to_yaml
      _yaml.to_file(app.app_actor_defaults_filepath)
    end

    def sync_roles!
      return unless parent.is_a?(App)
      debug_puts "preparing map..."
      _map = Actor.where(:template_actor_id.in => descendants.pluck(:_id))
        .pluck(:template_actor_id, :_id)
        .inject({}) do |hsh, ids|
          tpl_id, actor_id = ids
          hsh[tpl_id] ||= []
          hsh[tpl_id] << actor_id
          hsh
      end
      debug_puts "map prepared"

      # delete previous roles
      debug_puts "deleting existing roles on templated actors"
      ActorRole.where(:actor_id.in => _map.values.flatten).destroy_all

      debug_puts "re-creating roles to templated actors"
      _map.keys.each do |tpl_id|
        # all role mappings of any descendant below app/organizations
        ActorRole.where(:actor_id => tpl_id).each do |ar|
          debug_puts " - on #{tpl_id}"
          # create the same role maps to all tenant/organizations
          _map[tpl_id].each do |actor_id|
            debug_puts " - ActorRole actor_id: #{actor_id} role_id: #{ar.role_id}"
            ActorRole.create(actor_id: actor_id, role_id: ar.role_id)
          end
        end
      end
      _map
    end


  end

end
