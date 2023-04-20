# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_tenants
require 'swagger_helper'

controller = Api::V1::Apps::TenantsController
model = Actors::Tenant
serializer = TenantSerializer
overview_serializer = TenantSerializer

tag = 'Tenants'

describe 'Actors::Tenants API', swagger_doc: 'v1/swagger.json', "actors::tenants" => true  do

  path '/api/v1/apps/{app_id}/tenants' do

    get 'List Tenants of an App' do
      metadata[:operation]['x-candos'] = ["~/apps.admin", "~/app-tenant.admin"]
      metadata[:operation]['x-record-type'] = 'tenant'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin
        - ~/app-tenant.admin
        ---
        Controller: `Api::V1::Apps::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Tenant app_id"

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

  end

  path '/api/v1/apps/{app_id}/tenants/{id}' do

    get 'Show Tenant of an App' do
      metadata[:operation]['x-candos'] = ["~/apps.admin", "~/app-tenant.admin"]
      metadata[:operation]['x-record-type'] = 'tenant'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin
        - ~/app-tenant.admin
        ---
        Controller: `Api::V1::Apps::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Tenant app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Tenant id"

      response '200', 'Actors::Tenant view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update Tenant of an App' do
      metadata[:operation]['x-candos'] = ["~/apps.admin", "~/app-tenant.admin"]
      metadata[:operation]['x-record-type'] = 'tenant'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin
        - ~/app-tenant.admin
        ---
        Controller: `Api::V1::Apps::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Tenant app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Tenant id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [:short_name, :full_name, :image, :image_b64, :modules_selected],
                  required: []
                )

      response '200', 'Actors::Tenant updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Tenant of an App' do
      metadata[:operation]['x-candos'] = ["~/apps.admin", "~/app-tenant.admin"]
      metadata[:operation]['x-record-type'] = 'tenant'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin
        - ~/app-tenant.admin
        ---
        Controller: `Api::V1::Apps::TenantsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Tenant app_id"

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
