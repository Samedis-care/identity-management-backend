# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_admin_index
require 'swagger_helper'

controller = Api::V1::AppAdminController
model = Actors::App
serializer = AppAdminSerializer
overview_serializer = AppAdminOverviewSerializer

tag = 'Apps'

describe 'Actors::Apps API', swagger_doc: 'v1/swagger.json', "actors::apps" => true  do

  path '/api/v1/app_admin' do

    get 'List Apps' do
      metadata[:operation]['x-candos'] = ["identity-management/apps.reader"]
      metadata[:operation]['x-record-type'] = 'app_admin_overview'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/apps.reader
        ---
        Controller: `Api::V1::AppAdminController`

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

    post 'Create App' do
      metadata[:operation]['x-candos'] = ["identity-management/apps.writer"]
      metadata[:operation]['x-record-type'] = 'app_admin'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/apps.writer
        ---
        Controller: `Api::V1::AppAdminController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [:short_name, :full_name, :config, :import_roles, :import_candos, :locale_import_roles, :locale_import_candos],
                  #required: []
                )

      response '200', 'Actors::App created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/app_admin' do

    get 'Show App' do
      metadata[:operation]['x-candos'] = ["identity-management/apps.reader"]
      metadata[:operation]['x-record-type'] = 'app_admin'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/apps.reader
        ---
        Controller: `Api::V1::AppAdminController`

      EOM

      tags tag
      security [Bearer: []]
      
      response '200', 'Actors::App view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update App' do
      metadata[:operation]['x-candos'] = ["identity-management/apps.writer"]
      metadata[:operation]['x-record-type'] = 'app_admin'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/apps.writer
        ---
        Controller: `Api::V1::AppAdminController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [:short_name, :full_name, :config, :import_roles, :import_candos, :locale_import_roles, :locale_import_candos],
                  required: []
                )

      response '200', 'Actors::App updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete App' do
      metadata[:operation]['x-candos'] = ["identity-management/apps.deleter"]
      metadata[:operation]['x-record-type'] = 'app_admin'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/apps.deleter
        ---
        Controller: `Api::V1::AppAdminController`

      EOM

      tags tag
      security [Bearer: []]
      
      response '200', 'Actors::App deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
