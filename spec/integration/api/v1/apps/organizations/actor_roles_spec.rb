# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_organization_actor_roles
require 'swagger_helper'

controller = Api::V1::Apps::Organizations::ActorRolesController
model = Role
serializer = RoleSerializer
overview_serializer = RoleSerializer

tag = 'Roles'

describe 'Roles API', swagger_doc: 'v1/swagger.json', "roles" => true  do

  path '/api/v1/apps/{app_id}/organizations/{organization_id}/actor_roles' do

    get 'List Roles' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'role'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/actors.reader
        ---
        Controller: `Api::V1::Apps::Organizations::ActorRolesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "role app_id"

parameter name: "organization_id", in: :path,
          type: :string,
          required: true,
          description: "role organization_id"

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

    post 'Create role' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/actors.writer"]
      metadata[:operation]['x-record-type'] = 'role'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/actors.writer
        ---
        Controller: `Api::V1::Apps::Organizations::ActorRolesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "role app_id"

parameter name: "organization_id", in: :path,
          type: :string,
          required: true,
          description: "role organization_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "role id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [:role_id],
                  #required: []
                )

      response '200', 'Role created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/apps/{app_id}/organizations/{organization_id}/actor_roles/{id}' do

    get 'Show role' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'role'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/actors.reader
        ---
        Controller: `Api::V1::Apps::Organizations::ActorRolesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "role app_id"

parameter name: "organization_id", in: :path,
          type: :string,
          required: true,
          description: "role organization_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "role id"

      response '200', 'Role view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete role' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/actors.writer"]
      metadata[:operation]['x-record-type'] = 'role'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/actors.writer
        ---
        Controller: `Api::V1::Apps::Organizations::ActorRolesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "role app_id"

parameter name: "organization_id", in: :path,
          type: :string,
          required: true,
          description: "role organization_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "role id"

      response '200', 'Role deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
