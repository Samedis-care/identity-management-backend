# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_user_actors
require 'swagger_helper'

controller = Api::V1::Apps::Users::ActorsController
model = Actor
serializer = UserOrganizationSerializer
overview_serializer = UserOrganizationSerializer

tag = 'Actors'

describe 'Actors API', swagger_doc: 'v1/swagger.json', "actors" => true  do

  path '/api/v1/apps/{app_id}/users/{user_id}/actors' do

    get 'List Actors' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader+identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader+identity-management/actors.reader
        ---
        Controller: `Api::V1::Apps::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Actor app_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Actor user_id"

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

    post 'Create Actor' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader+identity-management/actors.writer"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader+identity-management/actors.writer
        ---
        Controller: `Api::V1::Apps::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Actor app_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Actor user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Actor id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'Actor created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/apps/{app_id}/users/{user_id}/actors/{id}' do

    get 'Show Actor' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader+identity-management/actors.reader"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader+identity-management/actors.reader
        ---
        Controller: `Api::V1::Apps::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Actor app_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Actor user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Actor id"

      response '200', 'Actor view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Actor' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/users.reader+identity-management/actors.writer"]
      metadata[:operation]['x-record-type'] = 'actor'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/users.reader+identity-management/actors.writer
        ---
        Controller: `Api::V1::Apps::Users::ActorsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Actor app_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Actor user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Actor id"

      response '200', 'Actor deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
