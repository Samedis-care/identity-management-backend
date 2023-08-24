require_relative 'boot'

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module IdentityManagement
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    config.i18n.default_locale = :en
    config.i18n.available_locales = %i[en de fr ru nl]
    config.i18n.fallbacks = %i[en de fr ru nl]

    # allows for defining `format` in locale yamls to get rid of attribute name in front
    config.active_model.i18n_customize_full_message = true

    # allows for defining `format` in locale yamls to get rid of attribute name in front
    config.active_model.i18n_customize_full_message = true

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    config.middleware.insert_after Rack::Sendfile, ActionDispatch::Cookies
    config.middleware.insert_after ActionDispatch::Cookies, ActionDispatch::Session::CookieStore

    config.middleware.insert_before 0, Class.new {
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, response = @app.call(env)

        headers['Strict-Transport-Security'] = ENV['HSTS_HEADER'] if ENV['HSTS_HEADER'].present?

        if ENV['CSP_HEADER'].present? || ENV['CSP_REPORT_ONLY_HEADER'].present?
          # Check if the requested URL matches the specific URL you want to set CSP for
          if env['REQUEST_PATH'].starts_with?('/api/v')
            # Set the default CSP header for API endpoints
            headers['Content-Security-Policy'] = ENV['CSP_HEADER'] if ENV['CSP_HEADER'].present?
            headers['Content-Security-Policy-Report-Only'] = ENV['CSP_REPORT_ONLY_HEADER'] if ENV['CSP_REPORT_ONLY_HEADER'].present?
          else
            # Set the CSP header for anything else (e.g. swagger api-docs or sidekiq ui)
            headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-src 'self'; object-src 'none'"
          end
        end

        [status, headers, response]
      end
    }

    # Skip views, helpers and assets when generating a new resource.
    config.after_initialize do
      Rails.application.routes.default_url_options[:host] = ENV['API_HOST'] || 'localhost:3000'
    end

    ########### SMTP SETTINGS ##################################
    config.action_mailer.delivery_method = (ENV['MAIL_DELIVERY']||:smtp).to_sym
    config.action_mailer.smtp_settings = {
        address: ENV['SMTP_HOST'],
        port: ENV['SMTP_PORT']||587,
        enable_starttls_auto: true,
        authentication: ENV['SMTP_AUTH']||:login,
        user_name: ENV['SMTP_USER'],
        password: ENV['SMTP_PASSWORD']
    }
    config.api_only = true
  end
end

# Use Oj JSON engine for best performance when calling #to_json
Oj.optimize_rails

# Mongoid migrations path
Mongoid::Migrator.migrations_path = ['db/migrate', 'config/apps/*/migrate']
