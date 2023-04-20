# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_tenant_organization_mappable_users
require 'swagger_helper'

controller = Api::V1::Apps::Tenants::Organizations::Picker::MappableUsersController
model = Actors::User
serializer = MappableUserOverviewSerializer
overview_serializer = MappableUserOverviewSerializer

tag = 'Actors'

describe 'Actors::Users API', swagger_doc: 'v1/swagger.json', "actors::users" => true  do

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/organizations/{organization_id}/picker/mappable_users' do

    get 'List Actors' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'mappable_user'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Organizations::Picker::MappableUsersController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Actor app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Actor tenant_id"

parameter name: "organization_id", in: :path,
          type: :string,
          required: true,
          description: "Actor organization_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]

      response '200', 'Actors::Users list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end


end
