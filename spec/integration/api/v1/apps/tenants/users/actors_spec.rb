# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_tenant_user_actors
require 'swagger_helper'

controller = Api::V1::Apps::Tenants::Users::ActorsController
model = Actors::Mapping
serializer = UserOrganizationSerializer
overview_serializer = UserOrganizationSerializer

tag = 'Mappings'

describe 'Actors::Mappings API', swagger_doc: 'v1/swagger.json', "actors::mappings" => true  do

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/users/{user_id}/actors' do

    get 'List Mappings' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping user_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type, :mapped_into_id, :user_id, :app_id, :tenant_id, :parent_template_actor_id, :cached_role_ids, :cached_role_names, :cached_candos]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type, :mapped_into_id, :user_id, :app_id, :tenant_id, :parent_template_actor_id, :cached_role_ids, :cached_role_names, :cached_candos]

      response '200', 'Actors::Mappings list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

    post 'Create Mapping' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Mapping id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'Actors::Mapping created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/users/{user_id}/actors/{id}' do

    get 'Show Mapping' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Mapping id"

      response '200', 'Actors::Mapping view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Mapping' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Mapping id"

      response '200', 'Actors::Mapping deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
