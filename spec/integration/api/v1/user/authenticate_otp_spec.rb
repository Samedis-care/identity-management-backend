# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_authenticate_otp_index
require 'swagger_helper'

controller = Api::V1::User::AuthenticateOtpController
model = Doorkeeper::AccessToken
serializer = AccountLoginSerializer
overview_serializer = 

tag = 'Current User'

describe 'Doorkeeper::AccessTokens API', swagger_doc: 'v1/swagger.json', "doorkeeper::accesstokens" => true  do

  path '/api/v1/user/authenticate_otp' do

    post 'Create Access Token' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'account_login'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::User::AuthenticateOtpController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'Doorkeeper::AccessToken created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end


end
