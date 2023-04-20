# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_apps
require 'swagger_helper'

controller = Api::V1::User::AppsController
model = Actors::App
serializer = AppSerializer
overview_serializer = AppSerializer

tag = 'Current User'

describe 'Actors::Apps API', swagger_doc: 'v1/swagger.json', "actors::apps" => true  do

  path '/api/v1/user/apps' do

    get 'List Apps' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'app'
      description <<~EOM
        Controller: `Api::V1::User::AppsController`

      EOM

      tags tag
      security [Bearer: []]
      
      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :parent_id, :parent_ids, :depth, :_keywords, :role_ids, :map_actor_id, :template_actor_id, :auto, :deleted, :deleted_at, :active, :name, :title, :short_name, :full_name, :path_ids, :path, :write_protected, :system, :image_data, :children_count, :actor_settings, :_type]

      response '200', 'Actors::Apps list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/user/apps' do

    put 'Update App' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'app'
      description <<~EOM
        Controller: `Api::V1::User::AppsController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  required: []
                )

      response '200', 'Actors::App updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
