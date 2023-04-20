# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_tenants
require 'swagger_helper'

controller = Api::V1::User::TenantsController
model = Actors::Tenant
serializer = ActorSerializer
overview_serializer = ActorOverviewSerializer

tag = 'Tenants'

describe 'Actors::Tenants API', swagger_doc: 'v1/swagger.json', "actors::tenants" => true  do

  path '/api/v1/user/tenant' do

    get 'List Tenants of the current user' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::User::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      
      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type, :modules_selected]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type, :modules_selected]

      response '200', 'Actors::Tenants list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

    post 'Create Tenant of the current user' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::User::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Tenant id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'Actors::Tenant created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/user/tenant/{id}' do

    get 'Show Tenant of the current user' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::User::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Tenant id"

      response '200', 'Actors::Tenant view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update Tenant of the current user' do
      metadata[:operation]['x-candos'] = ["identity-management/actors.writer", "~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/actors.writer
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::User::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Tenant id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  required: []
                )

      response '200', 'Actors::Tenant updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Tenant of the current user' do
      metadata[:operation]['x-candos'] = ["identity-management/actors.writer", "~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/actors.writer
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::User::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Tenant id"

      response '200', 'Actors::Tenant deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
