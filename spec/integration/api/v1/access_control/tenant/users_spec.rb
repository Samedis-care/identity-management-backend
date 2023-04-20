# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_access_control_tenant_users
require 'swagger_helper'

controller = Api::V1::AccessControl::Tenant::UsersController
model = User
serializer = TenantUserAccessSerializer
overview_serializer = TenantUserAccessOverviewSerializer

tag = 'Access Control'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/access_control/tenant/{tenant_id}/users' do

    get 'List User accounts authorized groups' do
      metadata[:operation]['x-candos'] = ["~/access-control.reader", "identity-management/apps.admin", "identity-management/global.admin"]
      metadata[:operation]['x-record-type'] = 'tenant_user_access_overview'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.reader
        - identity-management/apps.admin
        - identity-management/global.admin
        ---
        Controller: `Api::V1::AccessControl::Tenant::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "user account tenant_id"

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

  path '/api/v1/access_control/tenant/{tenant_id}/users/{id}' do

    get 'Show user account authorized groups' do
      metadata[:operation]['x-candos'] = ["~/access-control.reader", "identity-management/apps.admin", "identity-management/global.admin"]
      metadata[:operation]['x-record-type'] = 'tenant_user_access'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.reader
        - identity-management/apps.admin
        - identity-management/global.admin
        ---
        Controller: `Api::V1::AccessControl::Tenant::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "user account tenant_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

      response '200', 'User view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update user account authorized groups' do
      metadata[:operation]['x-candos'] = ["~/access-control.writer", "identity-management/apps.admin", "identity-management/global.admin"]
      metadata[:operation]['x-record-type'] = 'tenant_user_access'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.writer
        - identity-management/apps.admin
        - identity-management/global.admin
        ---
        Controller: `Api::V1::AccessControl::Tenant::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "user account tenant_id"

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

    delete 'Delete user account authorized groups' do
      metadata[:operation]['x-candos'] = ["~/access-control.writer", "identity-management/apps.admin", "identity-management/global.admin"]
      metadata[:operation]['x-record-type'] = 'tenant_user_access'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.writer
        - identity-management/apps.admin
        - identity-management/global.admin
        ---
        Controller: `Api::V1::AccessControl::Tenant::UsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "user account tenant_id"

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
