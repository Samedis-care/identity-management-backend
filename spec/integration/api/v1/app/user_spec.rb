# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_index
require 'swagger_helper'

controller = Api::V1::App::UserController
model = User
serializer = AppUserSerializer
overview_serializer = AppUserSerializer

tag = 'Current User'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/{app}/user' do

    get 'List User accounts' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::App::UserController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "user account app"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:id, :actor_id, :locale, :email, :gender, :title, :first_name, :last_name, :created_at]
      metadata[:operation]['x-gridfilter-fields'] = [:id, :actor_id, :locale, :email, :gender, :title, :first_name, :last_name, :created_at]

      response '200', 'Users list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/{app}/user' do

    get 'Show user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::App::UserController`

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

    put 'Update user account' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        Controller: `Api::V1::App::UserController`

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
                  only: [:app, :first_name, :last_name, :image, :image_b64, :gender, :email, :email_confirmation, :mobile, :title, :short, :otp_enable, :otp_disable],
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
        Controller: `Api::V1::App::UserController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "user account app"

      response '200', 'User deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
