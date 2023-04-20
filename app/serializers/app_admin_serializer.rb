class AppAdminSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :name,
    :short_name,
    :full_name,
    :languages,
    :available_languages
  )

  attribute :import_roles do |record|
    record.import_roles.to_yaml
  end

  attribute :locale_import_roles do |record|
    record.locale_import_roles.collect do |lang, data|
      [lang, { lang => data }.to_yaml]
    end.to_h
  end

  attribute :import_candos do |record|
    record.import_candos.to_yaml
  end

  attribute :locale_import_candos do |record|
    record.locale_import_candos.collect do |lang, data|
      [lang, { lang => data }.to_yaml]
    end.to_h
  end

  attribute :image do |record|
    {
      large: (record.image[:large].url rescue nil),
      medium: (record.image[:medium].url rescue nil),
      small: (record.image[:small].url rescue nil)
    }
  end

  attribute :config do |app|
    smtp_settings = app&.config.mailer&.smtp_settings&.delivery_method_options
    if smtp_settings
      smtp_settings[:password] = "-CENSORED-" unless smtp_settings[:password].blank?
    end

    {
      url: app&.config.url,
      uses_bearer_token: app&.config&.uses_bearer_token,

      locales: app&.config.locales,
      default_locale: app&.config.default_locale,

      mailer: {
        from: app&.config.mailer.from,
        reply_to: app&.config.mailer.reply_to,
        support_email: app&.config.mailer.support_email,
        logo_b64: app&.config.mailer.logo_b64,
        footer_html: app&.config.mailer.footer_html,
        footer_html_translations: app&.config.mailer.footer_html_translations,
        smtp_settings: smtp_settings
      },

      theme: {
        primary: app&.config&.theme&.primary.attributes.symbolize_keys.slice(:main, :light, :dark),
        secondary: app&.config&.theme&.secondary.attributes.symbolize_keys.slice(:main, :light, :dark),
        background: app&.config&.theme&.background.attributes.symbolize_keys.slice(:default),
        components_care: {
          ui_kit: {
            action_button: app&.config&.theme&.components_care&.ui_kit&.action_button.attributes.symbolize_keys.slice(:background_color),
          }
        },
        mode: app&.config&.theme&.mode
      }
    }
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_admin', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :name, default: 'app-name', description: 'unique name of the app'
          string :short_name, default: 'app-name', description: 'short name of the app'
          string :full_name, default: 'app-name', description: 'full name of the app'

          array :languages, default: %w(de en), description: 'language codes of configured locales' do
            items do
              string :locale, description: 'language code'
            end
          end
          array :available_languages, default: I18n.available_locales, description: 'language codes of supported locales' do
            items do
              string :locale, description: 'language code'
            end
          end

          string :import_candos,description: 'yaml data with array of all candos the app has'
          string :import_roles, description: 'yaml data with array of all roles the app has and assigned candos'

          object :locale_import_candos, description: 'language keys here are dynamic and can consist of any supported language, minimum should be those languages of the configured app locales' do
            string :en, description: 'the english locales for this apps functionalities as yaml string'
            string :de, description: 'the german locales for this apps functionalities as yaml string'
          end
          object :locale_import_roles, description: 'language keys here are dynamic and can consist of any supported language, minimum should be those languages of the configured app locales' do
            string :en, description: 'the english locales for this apps roles as yaml string'
            string :de, description: 'the german locales for this apps roles as yaml string'
          end

          object :config, description: 'Hash of app config' do
            string :url, default: 'https://domain.local', description: 'URL of the app'
            boolean :uses_bearer_token, default: true, description: 'If the app bearer token will be included in redirect URL as #anchor (true) or query param for server (false)'
            array :locales, default: %w(de en) do
              items do
                string :locale, description: 'locale string'
              end
            end
            string :default_locale, default: 'en', description: 'Which of the locales is the default'

            object :mailer, description: 'mail config' do
              string :from, description: 'The from address used in mails for user email confirmations'
              string :reply_to, description: 'The reply address used in mails for user email confirmations'
              string :support_email, description: 'The support address used in mails for user email confirmations'
              string :logo_b64, description: 'A PNG logo as mail header in Base64 encoded format'
              string :footer_html, description: 'The footer_html of the current client locale'

              object :footer_html_translations, description: 'language keys here are dynamic and can consist of any supported language, minimum should be those languages of the configured app locales' do
                string :en, description: 'the english locale footer'
                string :de, description: 'the german locale footer'
              end
              object :smtp_settings, description: 'smtp settings' do
                string :address, description: 'Address of SMTP server'
                number :port, description: 'Port of SMTP server'
                string :domain, description: 'HELO domain'
                string :user_name, description: 'SMTP username'
                string :password, description: 'SMTP password'
                string :authentication, description: 'AuthenticationMode: plain, login or cram_md5'
                boolean :enable_starttls, description: 'Use STARTTLS when connecting to your SMTP server and fail if unsupported'
                boolean :enable_starttls_auto, description: 'Detects if STARTTLS is enabled in your SMTP server and starts to use it'
                string :openssl_verify_mode, description: 'When using TLS, you can set how OpenSSL checks the certificate. This is really useful if you need to validate a self-signed and/or a wildcard certificate. You can use the name of an OpenSSL verify constant (\'none\' or \'peer\')'
                string :ssl, description: 'Enables the SMTP connection to use SMTP/TLS (SMTPS: SMTP over direct TLS connection)'
                number :open_timeout, description: 'Number of seconds to wait while attempting to open a connection.'
                number :read_timeout, description: 'Number of seconds to wait until timing-out a read(2) call.'
              end

            end

            object :theme, description: 'optional theme settings' do
              object :primary, description: 'primary colors' do
                string :main, description: 'primary color'
                string :light, description: 'lighter variant of the primary color'
                string :dark, description: 'darker variant of the primary color'
              end
              object :secondary, description: 'secondary colors' do
                string :main, description: 'secondary color'
                string :light, description: 'lighter variant of the secondary color'
                string :dark, description: 'darker variant of the secondary color'
              end
              object :background, description: 'secondary colors' do
                string :default, description: 'background color'
              end
              object :components_care, description: 'components care specific settings' do
                object :ui_kit, description: 'theme settings for ui_kit' do
                  object :action_button, description: 'theme settings for ActionButton' do
                    string :background_color, description: 'background color'
                  end
                end
              end
              string :type, default: 'light', description: 'light or dark theme as base'
            end

          end

        end
      }
    end

  end

end
