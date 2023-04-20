# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_role_functionalities
require 'swagger_helper'

controller = Api::V1::Apps::Roles::FunctionalitiesController
model = Functionality
serializer = FunctionalitySerializer
overview_serializer = FunctionalitySerializer

tag = 'Functionalities'

describe 'Functionalities API', swagger_doc: 'v1/swagger.json', "functionalities" => true  do

  path '/api/v1/apps/{app_id}/roles/{role_id}/functionalities' do

    get 'List Functionalities' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/roles.reader"]
      metadata[:operation]['x-record-type'] = 'functionality'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/roles.reader
        ---
        Controller: `Api::V1::Apps::Roles::FunctionalitiesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality app_id"

parameter name: "role_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality role_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :actors_app_id, :title, :description, :app, :module, :ident, :quickfilter, :_keywords, :role_ids]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :actors_app_id, :title, :description, :app, :module, :ident, :quickfilter, :_keywords, :role_ids]

      response '200', 'Functionalities list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

    post 'Create Functionality' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/roles.writer"]
      metadata[:operation]['x-record-type'] = 'functionality'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/roles.writer
        ---
        Controller: `Api::V1::Apps::Roles::FunctionalitiesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality app_id"

parameter name: "role_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality role_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Functionality id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [:functionality_id],
                  #required: []
                )

      response '200', 'Functionality created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/apps/{app_id}/roles/{role_id}/functionalities/{id}' do

    get 'Show Functionality' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/roles.reader"]
      metadata[:operation]['x-record-type'] = 'functionality'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/roles.reader
        ---
        Controller: `Api::V1::Apps::Roles::FunctionalitiesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality app_id"

parameter name: "role_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality role_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Functionality id"

      response '200', 'Functionality view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Functionality' do
      metadata[:operation]['x-candos'] = ["~/apps.admin+identity-management/roles.writer"]
      metadata[:operation]['x-record-type'] = 'functionality'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/apps.admin+identity-management/roles.writer
        ---
        Controller: `Api::V1::Apps::Roles::FunctionalitiesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality app_id"

parameter name: "role_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality role_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Functionality id"

      response '200', 'Functionality deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
