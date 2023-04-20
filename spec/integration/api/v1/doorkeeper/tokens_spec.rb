# Version: 1.0.5
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_token
require 'swagger_helper'

controller = Api::V1::Doorkeeper::TokensController
model = User
serializer = AppUserSerializer
overview_serializer = AppUserSerializer

tag = 'Access Tokens'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/{app}/oauth/token' do

    post 'Create User' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      
      tags tag
      security [Bearer: []]
      include_examples :path_ids, [:app]

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'User created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end


end
