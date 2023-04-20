# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_tenant_picker_user_v1_apps_tenants_picker_users_groups
require 'swagger_helper'

controller = Api::V1::Apps::Tenants::Picker::Users::GroupsController
model = Actors::Group
serializer = PickerUserGroupSerializer
overview_serializer = PickerUserGroupSerializer

tag = 'Groups'

describe 'Actors::Groups API', swagger_doc: 'v1/swagger.json', "actors::groups" => true  do

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/picker/users/{user_id}/groups' do

    get 'List Groups' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'picker_user_group'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/actors.reader
        ---
        Controller: `Api::V1::Apps::Tenants::Picker::Users::GroupsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Group app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Group tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Group user_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]

      response '200', 'Actors::Groups list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/picker/users/{user_id}/groups/{id}' do

    get 'Show Group' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'picker_user_group'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/actors.reader
        ---
        Controller: `Api::V1::Apps::Tenants::Picker::Users::GroupsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Group app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Group tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Group user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Group id"

      response '200', 'Actors::Group view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
