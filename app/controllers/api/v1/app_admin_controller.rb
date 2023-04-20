class Api::V1::AppAdminController < Api::V1::JsonApiController

  MODEL_BASE = Actors::App
  MODEL = ::Actors::App.available
  MODEL_OVERVIEW = ::Actors::App.available

  SERIALIZER = AppAdminSerializer
  OVERVIEW_SERIALIZER = AppAdminOverviewSerializer

  PERMIT_CREATE = PERMIT_UPDATE = [
    :short_name,
    :full_name,
    { config: [
        :url,
        :uses_bearer_token,
        :default_locale,
        {
          locales: [],
          mailer: [
            :from,
            :reply_to,
            :logo_b64,
            :footer_html,
            :footer_html_translations => {},
            :smtp_settings => [
              :address,
              :port,
              :domain,
              :user_name,
              :password,
              :authentication,
              :enable_starttls,
              :enable_starttls_auto,
              :openssl_verify_mode,
              :ssl,
              :open_timeout,
              :read_timeout
            ]
          ],
          theme: [
            { primary: [:main, :light, :dark] },
            { secondary: [:main, :light, :dark] },
            { background: [:default] },
            { components_care: [
                { ui_kit: [ { action_button: [:background_color]} ] }
              ]
            },
            :mode
          ]
        }
      ]
    },
    :import_roles,
    :import_candos,
    :locale_import_roles,
    :locale_import_candos
  ]

  private
  def cando
    CANDO.merge({
      index: %w(identity-management/apps.reader),
      show: %w(identity-management/apps.reader),
      create: %w(identity-management/apps.writer),
      update:  %w(identity-management/apps.writer),
      destroy: %w(identity-management/apps.deleter)
    })
  end

end
