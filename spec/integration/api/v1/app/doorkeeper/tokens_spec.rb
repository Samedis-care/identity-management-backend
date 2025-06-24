require 'swagger_helper'

describe 'Login API', swagger_doc: 'v1/swagger.json', users: true  do
  properties = {
      success: {type: :boolean},
      token: {type: :string},
      refresh_token: {type: :string},
      expires_in: {type: :number}
  }

  properties_msg = {
    meta: {
      type: :object,
      properties: {
        msg: { 
          type: :object,
          properties: {
            success: {type: :boolean}
          }
        }
      }
    }
  }

  path "/api/v1/{app}/oauth/token" do
    post 'Login user with email' do
      tags 'Access Tokens'

      parameter name: 'app', in: :path,
                type: :string,
                'x-example': 'identity-management',
                description: 'The app to login for.'

      parameter name: 'grant_type', in: :formData,
                type: :string,
                'x-example': 'password',
                enum: %w(password refresh_token google),
                description: 'Grant Type'

      parameter name: 'username', in: :formData,
                type: :string,
                'x-example': 'email@domain.local',
                description: 'The email that the user registered with'

      parameter name: 'email', in: :formData,
                type: :string,
                'x-example': 'email@domain.local',
                description: 'Alias for username'

      parameter name: 'password', in: :formData,
                type: :string,
                'x-example': '##################',
                description: 'Password'

      parameter name: 'invite_token', in: :formData,
                type: :string,
                description: 'Optional token for invites. Will be processed at login and passed through to frontend.'

      parameter name: 'refresh_token', in: :formData,
                type: :string,
                description: 'Refresh Token to be sent with grant_type "refresh_token" instead of email and password'

      response '200', 'User Logged in' do
        schema type: :object, properties:
        run_test!
      end

    end
  end

  path "/api/v1/oauth/revoke" do
    post 'Logout / invalidate the given token' do
      tags 'Access Tokens'
      security [Bearer: []]

      parameter name: 'access_token', in: :formData,
                type: :string,
                description: 'Token to be revoked (optional - falls back to current Bearer token in HTTP header)'

      response '200', 'Token revoked' do
        schema type: :object,
               properties: properties_msg
        run_test!
      end

    end
  end

end
