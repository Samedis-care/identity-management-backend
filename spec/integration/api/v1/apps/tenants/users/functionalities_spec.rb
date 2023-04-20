# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_tenant_user_functionalities
require 'swagger_helper'

controller = Api::V1::Apps::Tenants::Users::FunctionalitiesController
model = Functionality
serializer = FunctionalitySerializer
overview_serializer = FunctionalityOverviewSerializer

tag = 'Functionalities'

describe 'Functionalities API', swagger_doc: 'v1/swagger.json', "functionalities" => true  do

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/users/{user_id}/functionalities' do

    get 'List Functionalities' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'functionality'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Users::FunctionalitiesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality user_id"

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

  end

  path '/api/v1/apps/{app_id}/tenants/{tenant_id}/users/{user_id}/functionalities/{id}' do

    get 'Show Functionality' do
      metadata[:operation]['x-candos'] = ["~/app-tenant.admin", "~/tenant.admin"]
      metadata[:operation]['x-record-type'] = 'functionality'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/app-tenant.admin
        - ~/tenant.admin
        ---
        Controller: `Api::V1::Apps::Tenants::Users::FunctionalitiesController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality app_id"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality tenant_id"

parameter name: "user_id", in: :path,
          type: :string,
          required: true,
          description: "Functionality user_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Functionality id"

      response '200', 'Functionality view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
