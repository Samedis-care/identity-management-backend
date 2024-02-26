module Actors

  class App < Actor
    has_many :contents, inverse_of: :actors_app

    has_many :app_functionalities, class_name: 'Functionality', inverse_of: :actors_app, order: [:module.asc, :ident.asc]
    has_many :app_roles, class_name: 'Role', inverse_of: :actors_app, order: :name.asc

    embeds_one :config, autobuild: true

    def dump_path_candos
      "config/apps/#{name}/seeds"
    end
    def dump_path_roles
      "config/apps/#{name}/seeds"
    end
    def dump_path_cando_locales
      "config/apps/#{name}/locales/candos"
    end
    def dump_path_role_locales
      "config/apps/#{name}/locales/roles"
    end

    before_save do |record|
      record.parent = Actor.app_container if record.is_app?
    end

    class Config
      include Mongoid::Document
      embedded_in :app
      embeds_one :mailer, autobuild: true
      embeds_one :theme, autobuild: true

      def host
        _parent.host
      end

      class Mailer
        include Mongoid::Document

        attr_accessor :image

        validates_length_of :logo_b64, minimum: 1, maximum: 1.megabyte, allow_blank: true

        embeds_one :smtp_settings, autobuild: true, class_name: 'SmtpSettings'

        embedded_in :config
        field :from, type: String
        field :reply_to, type: String
        field :support_email, type: String
        field :logo_b64, type: String
        field :footer_html, type: String, localize: true

        # https://guides.rubyonrails.org/action_mailer_basics.html#:~:text=and%20Log4r%20loggers.-,smtp_settings,-Allows%20detailed%20configuration
        class SmtpSettings
          include Mongoid::Document

          embedded_in :mailer

          field :address, type: String
          field :port, type: Integer
          field :domain, type: String
          field :user_name, type: String
          field :password, type: String
          field :authentication, type: StringifiedSymbol
          field :enable_starttls, type: Boolean
          field :enable_starttls_auto, type: Boolean
          field :openssl_verify_mode, type: String
          field :ssl, type: Boolean
          field :open_timeout, type: Integer
          field :read_timeout, type: Integer

          def password=(_password)
            super(_password) unless _password == "-CENSORED-"
          end

          def delivery_method_options
            @delivery_method_options = begin
              _settings = attributes.symbolize_keys.except(:_id).reject{|_,v| v.is_a?(String) && v.blank? || v.nil? }
              return {} unless _settings[:address].present?
              _settings
            end
          end
        end

        def from
          @from ||= super ||"info@#{_parent.host}"
        end

        def reply_to
          @reply_to ||= super ||"no-reply@#{_parent.host}"
        end

        # logo must be locally stored as we don't want cloud interaction when sending
        # mails with the app logo
        # so form encoded uploads need to be converted to base64
        def logo_b64=(img)
          super Actors::App.ensure_base64(img)
        end

        def footer_html=(unsafe_html)
          _html = begin
            if unsafe_html.present?
              Actors::App.cleanup_html(unsafe_html)
            else
              nil
            end
          end
          super _html
        end
        def footer_html
          (Actors::App.cleanup_html super) || I18n.t("mailer.footer_html")
        end

        # fallbacks to locale yml content if available
        def footer_html_translations
          _footer = super
          if _footer.keys.empty?
            I18n.available_locales.map do |l|
              [l, I18n.t("mailer.footer_html", locale: l)]
            end.to_h
          else
            _footer
          end
        end


      end

      class Theme
        include Mongoid::Document
        embedded_in :config
        embeds_one :primary, autobuild: true
        embeds_one :secondary, autobuild: true
        embeds_one :background, autobuild: true
        embeds_one :components_care, autobuild: true

        field :mode, type: String, default: 'light'

        class Primary
          include Mongoid::Document
          embedded_in :theme
          field :main, type: String, default: "rgb(8, 105, 179)"
          field :dark, type: String, default: nil
          field :light, type: String, default: "rgb(57, 135, 194)"
        end
        class Secondary < Primary
          field :main, type: String, default: "rgb(185, 215, 240)"
          field :dark, type: String, default: nil
          field :light, type: String, default: nil
        end
        class Background
          include Mongoid::Document
          embedded_in :theme
          field :default, type: String, default: "rgb(185, 215, 240)"
        end
        class ComponentsCare
          include Mongoid::Document
          embedded_in :theme
          embeds_one :ui_kit, autobuild: true
          class UiKit
            include Mongoid::Document
            embedded_in :components_care
            embeds_one :action_button, autobuild: true
            class ActionButton
              include Mongoid::Document
              embedded_in :ui_kit
              field :background_color, type: String, default: "rgb(8, 105, 179)"
            end
          end
        end
      end

      field :url, type: String
      field :uses_bearer_token, type: Boolean, default: true
      field :locales, type: Array, default: ['de-DE']
      field :default_locale, type: String, default: 'de-DE'

      alias_attribute :bearer_token, :uses_bearer_token

      # default settings from yml
      def self.default_settings
        @@default_settings ||= YAML::load_file(::Rails.root.join('config', 'per_app_settings.yml'))
        @@default_settings.deep_symbolize_keys
      end

      def redirects
        @redirects = self.class.default_settings.dig :default_redirects
      end

    end

    def host
      @host ||= URI.parse(config&.url).host rescue '127.0.0.1'
    end

    def self.app_actor_defaults_path(app_name)
      "config/apps/#{app_name}/actor_defaults"
    end
    def app_actor_defaults_filepath
      "config/apps/#{name}/actor_defaults/#{name}.yml"
    end

    def required_documents
      Content.acceptance_required(self.name).keys
    end

    # remapping to association
    def functionalities
      app_functionalities
    end

    # remapping to association
    def roles
      app_roles
    end

    def tenants
      container_tenants.children.where(_type: Actors::Tenant)
    end

    def container_tenants
      children.find_by(_type: Actors::ContainerTenants)
    end

    def organization
      children.available.find_by(_type: Actors::Organization)
    end

    def admins
      children.where(name: 'app-admins', _type: Actors::Group).first
    end

    def tenant_admins
      children.where(name: 'tenant-admins', _type: Actors::Group).first
    end

    def enterprises
      container_enterprises.children.where(_type: Actors::Enterprise)
    end

    def container_enterprises
      children.find_by(_type: Actors::ContainerEnterprises)
    end

    def app_container_users
      children.where(name: :users, _type: Actors::Group).first
    end

    def container_users
      app_container_users
    end

    def users
      ::User.where(:actor_id.in => container_users.children.mappings.pluck(:map_actor_id))
    end

    def self.im
      find_by(name: 'identity-management')
    end

    # the 2 letter language ident of the configured default locale
    def default_language
      @default_language ||= (config&.default_locale || I18n.default_locale).to_s.split('-').first.downcase
    end

    # the 2 letter language idents of the configured app locales
    # default locale with be the first
    def languages
      @languages ||= begin
        config.reload if config.persisted?
        ([default_language] + config.locales.collect {|l| l.to_s.split('-').first.downcase }.sort).compact.uniq
      end
    end

    def available_languages
      @available_languages ||= I18n.available_locales.collect &:to_s
    end

    # helper to build schema validations for required language keys in an object
    def language_json_schema
      languages.collect do |l|
        # only first (primary language is required)
        if languages.first.eql?(l)
          [l, { type: :string }]
        else
          [l, { anyOf: [{ type: :string }, { type: :null }] }]
        end
      end.to_h
    end

    # helper to filter localized mongoid field hashes
    # to only leave language data the app is configured for
    # and ensure all language keys present with empty values
    def translations(data={})
      @translations ||= languages.collect{|k| [k,nil] }.to_h
      @translations.merge(data.slice(*languages))
    end

    def auto_translate_organization!
      self.organization.descendants.each do |_actor|
        ap "#{_actor.name} - #{self.languages} - #{_actor.path}"
        ap _actor.title_translation_auto *self.languages
        _actor.save validate: false
        puts "-" *80
      end
    end

    # Schema used to verify YML format for role seed
    def role_schema
      Role::SeedSchema.schema(self).to_h
    end

    # Schema used to verify YML format for role locales
    def role_locale_schema
      Role::LocaleSchema.schema(self).to_h
    end

    # Schema used to verify YML format for cando seed
    def cando_schema
      Functionality::SeedSchema.schema(self).to_h
    end

    # Schema used to verify YML format for cando locales
    def cando_locale_schema
      Functionality::LocaleSchema.schema(self).to_h
    end

    # Helper regex to validate if a cando is properly formatted
    def cando_regex
      Regexp.new("^#{self.name}/[a-z\-]+\.[a-z\-]+$")
    end

    # Getter for turning this app's roles to yaml
    def import_roles
      app_roles.available
               .includes(:functionalities)
               .collect(&:seed_dump)
    end

    # Setter to import YML formatted roles into the app
    def import_roles=(data)
      _yaml_data = data.is_a?(Hash) ? data : YAML.load(data)
      # this will throw an exception if the data isn't valid to the schema
      _yaml_data.each do |role|
        begin
          JSON::Validator.validate!(role_schema, role)
        rescue => e
          puts "=" * 80
          puts "Error at role: #{JSON.pretty_generate(role)}"
          puts "-" * 80
          puts JSON.pretty_generate(role_schema)
          puts "=" * 80
          puts e.message
          raise e
        end
      end

      _yaml_data.each do |r|
        r = r.with_indifferent_access
        puts "importing role named: #{r[:name]}"
        role = roles.named(r[:name]).first_or_initialize
        role.attributes = r.slice(:name, :title, :title_translations, :description_translations)
        role.functionality_ids = r[:candos].collect do |c|
          f = app_functionalities.available.cando(c).first_or_create(title:"IMPORTED: #{c}", description:"IMPORTED: #{c}")
          f.id
        end.uniq.sort
        role.save!
      end
      # cache expiry
      ::User.cache_expire!
      true
    end

    # Getter for turning this app's roles locales to yaml
    def locale_import_roles
      _locales = translations.dup
      app_roles.order(name: 1).each do |role|
        _rld = role.locale_dump
        _locales.each do |l, _|
          _locales[l] ||= {}
          _locales[l].merge! _rld[l].compact # remove nil values
        end
      end
      _locales
    end

    # Setter to import YML formatted role locales into the app
    def locale_import_roles=(data)
      _yaml_data = data.is_a?(String) ? YAML.load(data) : data

      # this will throw an exception if the data isn't valid to the schema
      JSON::Validator.validate!(role_locale_schema, _yaml_data)

      _yaml_data.slice(*languages).each do |l, role_locales|
        I18n.locale = l
        role_locales.each do |role_name, attrs|
          r = app_roles.available.includes(:functionalities).find_by(name: role_name)
          next unless r.is_a?(Role)
          r.attributes = attrs.slice(*%w(title description)).reject{|k,v|v.blank?}.compact
          r.save! if r.changes.any?
        end
      end
      I18n.locale = I18n.default_locale
      true
    end

    # Seeds roles of an app via YML file into the database
    def seed_roles!
      _file = "#{dump_path_roles}/roles.yml"
      return false unless File.exist? _file rescue debugger
      puts "Seeding Roles for: #{name}"
      _yaml_data = File.read _file
      self.import_roles=(_yaml_data)
      true
    end

    # Seeds roles of all apps via YML files into the database
    def self.seed_roles!
      available.each do |app|
        app.seed_roles!
      end
    end

    # Writes the role locales of this app into YML files (one per language)
    def dump_role_locales
      FileUtils.mkdir_p dump_path_role_locales
      _roles = locale_import_roles
      return unless _roles.any?
      _roles.each do |lang, locales|
        { lang => locales }.to_yaml.to_file "#{dump_path_role_locales}/#{lang}.yml"
      end
    end

    # Writes the role locales of all apps into YML files (app dir with one file per language)
    def self.dump_role_locales
      available.each do |app|
        app.dump_role_locales
      end
    end

    # Writes dumps of an app's roles to YML file
    def dump_roles
      FileUtils.mkdir_p dump_path_roles
      _roles = import_roles
      return unless _roles.any?
      _roles.to_yaml.to_file "#{dump_path_roles}/roles.yml"
    end

    # Writes each app's roles to YML files
    def self.dump_roles
      available.each do |app|
        app.dump_roles
      end
    end

    # Updates the locales of an app's roles
    def seed_role_locales!
      Dir.glob("#{dump_path_role_locales}/*.yml").each do |yml_file|
        _locale = File.basename(yml_file, '.yml')
        puts "Seeding Role locales for (#{_locale}) app: #{name} from #{"#{dump_path_role_locales}/*.yml"}"
        self.locale_import_roles= File.read(yml_file)
      end
    end

    # Updates the locales of each app's roles
    def self.seed_role_locales!
      available.each do |app|
        app.seed_role_locales!
      end
    end

    # All app candos as a Hash
    def import_candos
      app_functionalities.available.collect(&:seed_dump)
    end

    # Updates or creates app candos from a YML String or Hash
    def import_candos=(data)
      _yaml_data = data.is_a?(String) ? YAML.load(data) : data

      # this will throw an exception if the data isn't valid to the schema
      _yaml_data.each do |cando|
        begin
          JSON::Validator.validate!(cando_schema, cando)
        rescue => e
          puts "=" * 80
          puts "Error at cando: #{JSON.pretty_generate(cando)}"
          puts "=" * 80
          raise e
        end
      end
      _yaml_data.each do |c|
        c = c.with_indifferent_access
        f = app_functionalities.available.cando(c[:cando]).first_or_initialize
        f.attributes = c.slice(:title, :description)
        f.save!
      end
      true
    end

    # All locales to the candos of an app as a Hash
    def locale_import_candos
      _locales = translations.dup
      app_functionalities.order(module: 1, ident: 1).each do |func|
        _fld = func.locale_dump
        _locales.each do |l, _|
          _locales[l] ||= {}
          _locales[l].merge! _fld[l].compact # remove nil values
        end
      end
      _locales
    end

    # Updates or creates app cando locales from a YML String or Hash
    def locale_import_candos=(data)
      _yaml_data = data.is_a?(String) ? YAML.load(data) : data

      # this will throw an exception if the data isn't valid to the schema
      JSON::Validator.validate!(cando_locale_schema, _yaml_data)

      _yaml_data.slice(*languages).each do |l, candos|
        I18n.locale = l
        candos.each do |c, attrs|
          f = app_functionalities.available.cando(c).first
          next unless f.is_a?(Functionality)
          f.attributes = attrs.slice(*%w(title description)).reject{|k,v|v.blank?}.compact
          f.save! if f.changes.any?
        end
      end
      I18n.locale = I18n.default_locale
      true
    end

    # Writes the cando locales of this app to one YML file per language
    def dump_cando_locales
      FileUtils.mkdir_p dump_path_cando_locales
      _candos = locale_import_candos
      return unless _candos.any?
      _candos.each do |lang, locales|
        { lang => locales }.to_yaml.to_file "#{dump_path_cando_locales}/#{lang}.yml"
      end
    end

    # Writes each app's cando locales to one YML file per language
    def self.dump_cando_locales
      available.each do |app|
        app.dump_cando_locales
      end
    end

    # Imports all locales of an app's candos from YML files into database
    def seed_cando_locales!
      Dir.glob("#{dump_path_cando_locales}/*.yml").each do |yml_file|
        _locale = File.basename(yml_file, '.yml')
        puts "Seeding Cando locales (#{_locale}) for app: #{name}"
        self.locale_import_candos= File.read(yml_file)
      end
    end

    # Imports all locales of each app's candos from YML files into database
    def self.seed_cando_locales!
      available.each do |app|
        app.seed_cando_locales!
      end
    end

    # Writes seed files of candos for an app to YML files
    def dump_candos
      FileUtils.mkdir_p dump_path_candos
      _candos = import_candos
      return unless _candos.any?
      _candos.to_yaml.to_file "#{dump_path_candos}/candos.yml"
    end

    # Writes seed files of candos for each app to YML files
    def self.dump_candos
      FileUtils.mkdir_p dump_path_candos
      available.each do |app|
        app.dump_candos
      end
    end

    # Imports all candos for this app from YML files into database
    def seed_candos!
      _file = "#{dump_path_candos}/candos.yml"
      return false unless File.exist? _file

      _yaml_data = YAML.load_file _file
      self.import_candos=(_yaml_data)
      true
    end

    # Imports all candos of each app from YML files into database
    def self.seed_candos!
      Dir.glob("#{dump_path_candos}/candos.yml").each do |yml_file|
        _app_name = File.basename(yml_file, '.yml')
        _app = find_by name: _app_name
        puts "Seeding Candos for: #{_app.name}"
        _app.seed_candos!
      end
    end

    # dump everything of this app into YML files
    def dump
      dump_roles
      dump_role_locales
      dump_candos
      dump_cando_locales
    end

    # dump everything of each app into YML files
    def self.dump
      available.each &:dump
    end

    def self.ensure_im_app!
      # Create Admin account
      ::User.global_admin.set(system: true, actor_id: Actors::User.global_admin.id)
      Actors::User.global_admin.set(system: true)

      app_im = Actors::App.available.named('identity-management').first_or_create(
        system: true,
        short_name: 'identity-management',
        parent: Actors::App.app_container
      )

      app_im.ensure_defaults!

      # ensure default admin tenant with the default admin user as member
      admin_tenant = Actors::Tenant.where(name: 'system', parent: app_im.container_tenants).first_or_initialize(
        short_name: 'System',
        full_name: 'System',
        title: 'System',
        system: true
      )
      admin_tenant.save
      admin_tenant.ensure_defaults!
      admin_tenant.organization.ensure_defaults!

      app_im.admins.map_into! Actors::User.global_admin
    end

    def access_control
      @access_control ||= AccessControl.for_app(id)
    end

    # seed everything of this app from YML files to database
    def seed!
      ensure_defaults!
      _original_locales = config.locales.dup
      config.locales = %w(en-US de-DE fr-FR ru-RU nl-NL)
      seed_roles!
      seed_role_locales!
      seed_candos!
      seed_cando_locales!
      config.locales = _original_locales
      ensure_defaults!
      self.organization.app_defaults_import!
    end

    # seed everything of each app from YML files to database
    def self.seed!
      ensure_im_app!
      available.each &:seed!
      ensure_im_app!
    end

    def self.apps_for_views
      available.where(:name.ne => 'identity-management')
    end

    def self.create_app_views!
      apps_for_views.each &:create_app_view!
    end

    def self.drop_app_views!
      apps_for_views.each &:drop_app_view!
    end

    def view_name
      "view_#{name.underscore}_actors"
    end

    def create_app_view!
      _command = {
        create: view_name,
        viewOn: 'actors',
        pipeline: [
          {
            '$match' => {
              'deleted' => false
            }
          }, {
            '$match' => {
              '$or' => [
                { '_id' => id },
                { 'parent_ids' => id },
              ]
            }
          }
        ]
      }
      drop_app_view! # drop if exists
      Mongoid.client(:default).command **_command
    end

    def drop_app_view!
      Mongoid.client(:default)[view_name].drop
    end

  end

end
