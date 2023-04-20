# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_access_control_tenant_groups
require 'swagger_helper'

controller = Api::V1::AccessControl::Tenant::GroupsController
model = AccessControl
serializer = AccessControlSerializer
overview_serializer = AccessControlSerializer

tag = 'Access Control'

describe 'AccessControls API', swagger_doc: 'v1/swagger.json', "accesscontrols" => true  do

  path '/api/v1/access_control/tenant/{tenant_id}/groups' do

    get 'List Access control available groups of this tenant' do
      metadata[:operation]['x-candos'] = ["~/access-control.reader"]
      metadata[:operation]['x-record-type'] = 'access_control'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.reader
        ---
        Controller: `Api::V1::AccessControl::Tenant::GroupsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Access control tenant_id"

      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query

      response '200', 'AccessControls list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end


end
