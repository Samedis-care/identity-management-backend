class AppInfoSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :name,
    :short_name,
    :full_name
  )

  attribute :image do |record|
    {
      large: (record.image_url(:large) rescue nil),
      medium: (record.image_url(:medium) rescue nil),
      small: (record.image_url(:small) rescue nil)
    }
  end

  attribute :config do |app|
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
        footer_html_translations: app&.config.mailer.footer_html_translations
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

  attribute :contents do |app|
    app.contents.latest.collect do |c|
      {
        id: c.dig(:content_id).to_s,
        name: c.dig(:_id),
        url: app.url_helpers.v1_app_content_url(app.id, c.dig(:content_id)),
        version: c.dig(:version)
      }
    end
  end

  attribute :auth_provider_hints do |app|
    CustomAuthProvider.all.collect(&:trusted_domain_checksums).flatten
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_info', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :name, default: 'app-name', description: 'unique name of the app'
          string :short_name, default: 'app-name', description: 'short name of the app'
          string :full_name, default: 'app-name', description: 'full name of the app'

          array :auth_provider_hints, description: 'MD5 checksums for domains with custom oauth provider' do
            items do
              string :checksum
            end
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


          array :contents do
            items do
              object do
                string :id, description: 'id of the content'
                string :name, description: 'name of the content (e.g. tos)'
                string :url, description: 'url to load the content'
                string :version, description: 'the version (latest) of the content'
              end
            end
          end

        end
      }
    end

  end

end
