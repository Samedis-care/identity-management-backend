# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_register
require 'swagger_helper'

controller = Api::V1::Devise::RegistrationsController
model = User
serializer = AppUserSerializer
overview_serializer = AppUserSerializer

tag = 'User accounts'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/register' do

    post 'Create user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::Devise::RegistrationsController`

      EOM

      tags tag
      security [Bearer: []]
      
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

  path '/api/v1/register' do

    put 'Update user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::Devise::RegistrationsController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  required: []
                )

      response '200', 'User updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::Devise::RegistrationsController`

      EOM

      tags tag
      security [Bearer: []]
      
      response '200', 'User deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
