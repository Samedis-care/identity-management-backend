# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_tenant_invitations
require 'swagger_helper'

controller = Api::V1::App::Tenant::InvitationsController
model = Invite
serializer = InvitationSerializer
overview_serializer = InvitationSerializer

tag = 'Invite'

describe 'Invites API', swagger_doc: 'v1/swagger.json', "invites" => true  do

  path '/api/v1/{app}/tenant/{tenant_id}/invitations' do

    post 'Create Invite' do
      metadata[:operation]['x-candos'] = ["~/access-control.writer", "~/tenant.admin", "~/app-tenant.admin"]
      metadata[:operation]['x-record-type'] = 'invitation'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.writer
        - ~/tenant.admin
        - ~/app-tenant.admin
        ---
        Controller: `Api::V1::App::Tenant::InvitationsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "Invite app"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Invite tenant_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Invite id"

      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'Invite created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/{app}/tenant/{tenant_id}/invitations/{id}' do

    delete 'Delete Invite' do
      metadata[:operation]['x-candos'] = ["~/access-control.writer", "~/tenant.admin", "~/app-tenant.admin"]
      metadata[:operation]['x-record-type'] = 'invitation'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - ~/access-control.writer
        - ~/tenant.admin
        - ~/app-tenant.admin
        ---
        Controller: `Api::V1::App::Tenant::InvitationsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "app", in: :path,
          type: :string,
          required: true,
          description: "Invite app"

parameter name: "tenant_id", in: :path,
          type: :string,
          required: true,
          description: "Invite tenant_id"

parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Invite id"

      response '200', 'Invite deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
