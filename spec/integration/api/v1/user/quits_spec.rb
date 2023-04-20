# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_quit
require 'swagger_helper'

controller = Api::V1::User::QuitsController
model = User
serializer = AppSerializer
overview_serializer = 

tag = 'Current User'

describe 'Users API', swagger_doc: 'v1/swagger.json', "users" => true  do

  path '/api/v1/user/quits/{id}' do

    delete 'Delete user account' do
      metadata[:operation]['x-candos'] = ["public"]
      metadata[:operation]['x-record-type'] = 'app'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - public
        ---
        Controller: `Api::V1::User::QuitsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "user account id"

      response '200', 'User deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
