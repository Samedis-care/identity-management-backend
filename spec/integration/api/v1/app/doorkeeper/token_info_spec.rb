# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_info
require 'swagger_helper'

controller = Api::V1::App::Doorkeeper::TokenInfoController
model = User
serializer = AppUserSerializer
overview_serializer = AppUserSerializer

tag = 'Access Tokens'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/{app}/oauth/token/info' do

    get 'Show user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::App::Doorkeeper::TokenInfoController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "user account app"

      response '200', 'User view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
