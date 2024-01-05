require 'rails_helper'

Rails.application.config.to_prepare do
  require 'json_api'
end

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.to_s + '/swagger'

  config.openapi_strict_schema_validation = false

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:to_swagger' rake task, the complete Swagger will
  # be generated at the provided relative path under swagger_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a swagger_doc tag to the
  # the root example_group in your specs, e.g. describe '...', swagger_doc: 'v2/swagger.json'
  config.openapi_specs = {
    'v1/swagger.json' => {
      swagger: '2.0',
      info: {
        title: 'API V1',
        version: 'v1',
        description: '# Obtaining a Bearer token

To obtain a Bearer authentication token for your users you need to redirect them to the Identity Management login page: `https://ident.services/login/{APP_NAME}`. The site takes the following optional query parameters:
- `redirect_host`: The target redirection URL (e.g. `https://my-app/user/visited/this/without/session`). The target hostname is validated against a whitelist. If the supplied hostname is not on the whitelist the user is redirected to the domain linked with your application.

After the user logged in he is redirected to `/authenticated` on your site. The following parameters are passed as anchor (accessible via `window.location.hash` in your frontend):
- `token` (string): The user Bearer token
- `token_expire` (Unix Timestamp in milliseconds) The expire date of the token
- `refresh_token` (string): Token to obtain a new Bearer token
- `remember_me` (boolean): Has the user checked remember me? If true you should persist the `token`, `token_expire` and `refresh_token`, otherwise you should store them as client side cookies to remove them as the user closes his browser.
- `redirect_path` (string, may be empty): Pathname of the URL passed to the login site as `redirect_host` (e.g. `/user/visited/this/without/session`)
- `invite_token` (string, may be empty): User invitation token (if login comes from an invite email)

# Refreshing the Bearer token

To refresh the Bearer token using a `refresh_token` please refer to the API documentation for the following endpoint `/api/v1/{APP_NAME}/oauth/token`'
      },
      paths: {},
      securityDefinitions: {
        Bearer: {
          description: 'Token based authentication Header. Authenticate and then copy the token into this field and prefix with "Bearer " and a space.',
          type: :apiKey,
          name: 'Authorization',
          in: :header
        }
      }
    }
  }
end
