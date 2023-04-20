# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_user_confirmation
require 'swagger_helper'

controller = Api::V1::Devise::ConfirmationsController
model = User
serializer = AppUserSerializer
overview_serializer = AppUserSerializer

tag = 'User accounts'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/{app}/users/confirmation' do

    post 'Create user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::Devise::ConfirmationsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "user account app"

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

  path '/api/v1/{app}/users/confirmation' do

    get 'Show user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::Devise::ConfirmationsController`

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
