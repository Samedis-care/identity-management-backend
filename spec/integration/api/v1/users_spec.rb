# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_users
require 'swagger_helper'

controller = Api::V1::UsersController
model = User
serializer = UserSerializer
overview_serializer = UserOverviewSerializer

tag = 'User accounts'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/users' do

    get 'List User accounts' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/users.reader"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/users.reader
        ---
        Controller: `Api::V1::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      
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

    post 'Create user account' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/users.writer"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/users.writer
        ---
        Controller: `Api::V1::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

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

  path '/api/v1/users/{id}' do

    get 'Show user account' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/users.reader"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/users.reader
        ---
        Controller: `Api::V1::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

      response '200', 'User view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update user account' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/users.writer"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/users.writer
        ---
        Controller: `Api::V1::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

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
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/users.deleter"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/users.deleter
        ---
        Controller: `Api::V1::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

      response '200', 'User deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
