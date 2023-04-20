# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_user_roles
require 'swagger_helper'

controller = Api::V1::Apps::Users::RolesController
model = Role
serializer = RoleSerializer
overview_serializer = RoleOverviewSerializer

tag = 'Roles'

describe 'Roles API', swagger_doc: 'v1/swagger.json', "roles" => true  do

  path '/api/v1/apps/{app_id}/users/{user_id}/roles' do

    get 'List Roles' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader+identity-management/roles.reader"]
      metadata[:operation]['x-record-type'] = 'role'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader+identity-management/roles.reader
        ---
        Controller: `Api::V1::Apps::Users::RolesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "role app_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "role user_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :actors_app_id, :app, :title, :description, :name, :write_protected, :system, :_keywords, :functionality_ids]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :actors_app_id, :app, :title, :description, :name, :write_protected, :system, :_keywords, :functionality_ids]

      response '200', 'Roles list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/apps/{app_id}/users/{user_id}/roles/{id}' do

    get 'Show role' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader+identity-management/roles.reader"]
      metadata[:operation]['x-record-type'] = 'role'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader+identity-management/roles.reader
        ---
        Controller: `Api::V1::Apps::Users::RolesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "role app_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "role user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "role id"

      response '200', 'Role view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
