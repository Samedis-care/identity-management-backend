# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_content_acceptance
require 'swagger_helper'

controller = Api::V1::App::ContentAcceptanceController
model = Content
serializer = ContentAcceptanceSerializer
overview_serializer = 

tag = 'Current User'

describe 'Contents API', swagger_doc: 'v1/swagger.json', "contents" => true  do

  path '/api/v1/{app}/content_acceptance/{name}' do

    post 'Create Content' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'content_acceptance'
      description <<~EOM
        Controller: `Api::V1::App::ContentAcceptanceController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "Content app"

parameter name: "name", in: :path,
          type: :string,
          required: true,
          description: "Content name"

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

  path '/api/v1/{app}/content_acceptance/{name}' do

    get 'Show Content' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'content_acceptance'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::App::ContentAcceptanceController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "Content app"

parameter name: "name", in: :path,
          type: :string,
          required: true,
          description: "Content name"

      response '200', 'Content view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update Content' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'content_acceptance'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::App::ContentAcceptanceController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "Content app"

parameter name: "name", in: :path,
          type: :string,
          required: true,
          description: "Content name"

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

  end

end
