# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_access_control_groups
require 'swagger_helper'

controller = Api::V1::AccessControl::App::GroupsController
model = AccessControl
serializer = AccessControlSerializer
overview_serializer = AccessControlSerializer

tag = 'Access Control'

describe 'AccessControls API', swagger_doc: 'v1/swagger.json', "accesscontrols" => true  do

  path '/api/v1/access_control/app/{name}/groups' do

    get 'List Access control available groups for this app' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin", "~/access-control.reader", "~/notifications.writer"]
      metadata[:operation]['x-record-type'] = 'access_control'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin
        - ~/access-control.reader
        - ~/notifications.writer
        ---
        Controller: `Api::V1::AccessControl::App::GroupsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "name", in: :path,
          type: :string,
          required: true,
          description: "Access control name"

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
