# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_picker_actors
require 'swagger_helper'

controller = Api::V1::Picker::ActorsController
model = Actor
serializer = ActorSerializer
overview_serializer = ActorOverviewSerializer

tag = 'Actors'

describe 'Actors API', swagger_doc: 'v1/swagger.json', "actors" => true  do

  path '/api/v1/picker/actors' do

    get 'List Actors' do
      metadata[:operation]['x-candos'] = ["identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/actors.reader
        ---
        Controller: `Api::V1::Picker::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      
      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]

      response '200', 'Actors list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/picker/actors' do

    get 'Show Actor' do
      metadata[:operation]['x-candos'] = ["identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/actors.reader
        ---
        Controller: `Api::V1::Picker::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      
      response '200', 'Actor view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
