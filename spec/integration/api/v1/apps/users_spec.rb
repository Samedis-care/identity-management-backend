# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_users
require 'swagger_helper'

controller = Api::V1::Apps::UsersController
model = User
serializer = AppUserSerializer
overview_serializer = UserOverviewSerializer

tag = 'User accounts'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/apps/{app_id}/users' do

    get 'List User accounts' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader
        ---
        Controller: `Api::V1::Apps::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "user account app_id"

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

  path '/api/v1/apps/{app_id}/users/{id}' do

    get 'Show user account' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader
        ---
        Controller: `Api::V1::Apps::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "user account app_id"

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
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.writer"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.writer
        ---
        Controller: `Api::V1::Apps::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "user account app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [:image_b64, :image, :pwd_reset_uid, :active, :email, :picture, :locale, :set_password, :new_password, :new_password_verify, :title, :first_name, :last_name, :short, :gender, :invalid_at],
                  required: []
                )

      response '200', 'User updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete user account' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.writer"]
      metadata[:operation]['x-record-type'] = 'user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.writer
        ---
        Controller: `Api::V1::Apps::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "user account app_id"

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
