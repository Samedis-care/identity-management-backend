# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_picker_actor_mappings
require 'swagger_helper'

controller = Api::V1::Picker::MappingsController
model = Actors::Mapping
serializer = ActorMappingsSerializer
overview_serializer = ActorMappingsSerializer

tag = 'Mappings'

describe 'Actors::Mappings API', swagger_doc: 'v1/swagger.json', "actors::mappings" => true  do

  path '/api/v1/picker/actors/{actor_id}/mappings' do

    get 'List Mappings' do
      metadata[:operation]['x-candos'] = ["identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'actor_mappings'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/actors.reader
        ---
        Controller: `Api::V1::Picker::MappingsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "actor_id", in: :path,
          type: :string,
          required: true,
          description: "Mapping actor_id"

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

  end


end
