# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_contents
require 'swagger_helper'

controller = Api::V1::Apps::ContentsController
model = Content
serializer = ContentSerializer
overview_serializer = ContentSerializer

tag = 'Content'

describe 'Contents API', swagger_doc: 'v1/swagger.json', "contents" => true  do

  path '/api/v1/apps/{app_id}/contents' do

    get 'List Content' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/contents.reader"]
      metadata[:operation]['x-record-type'] = 'content'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/contents.reader
        ---
        Controller: `Api::V1::Apps::ContentsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Content app_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :actors_app_id, :app, :name, :content, :content_de, :content_en, :version, :acceptance_required, :active, :_keywords]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :actors_app_id, :app, :name, :content, :content_de, :content_en, :version, :acceptance_required, :active, :_keywords]

      response '200', 'Contents list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

    post 'Create Content' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/contents.writer"]
      metadata[:operation]['x-record-type'] = 'content'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/contents.writer
        ---
        Controller: `Api::V1::Apps::ContentsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Content app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Content id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'Content created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/apps/{app_id}/contents/{id}' do

    get 'Show Content' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'content'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::Apps::ContentsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Content app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Content id"

      response '200', 'Content view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update Content' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/contents.writer"]
      metadata[:operation]['x-record-type'] = 'content'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/contents.writer
        ---
        Controller: `Api::V1::Apps::ContentsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Content app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Content id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  required: []
                )

      response '200', 'Content updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Content' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/contents.deleter"]
      metadata[:operation]['x-record-type'] = 'content'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/contents.deleter
        ---
        Controller: `Api::V1::Apps::ContentsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Content app_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Content id"

      response '200', 'Content deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
