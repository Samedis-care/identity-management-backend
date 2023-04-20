# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_account_logins
require 'swagger_helper'

controller = Api::V1::User::AccountLoginsController
model = Doorkeeper::AccessToken
serializer = AccountLoginSerializer
overview_serializer = AccountLoginSerializer

tag = 'Account Logins'

describe 'Doorkeeper::AccessTokens API', swagger_doc: 'v1/swagger.json', "doorkeeper::accesstokens" => true  do

  path '/api/v1/user/account_logins' do

    get 'List Access Tokens' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'account_login'
      description <<~EOM
        Controller: `Api::V1::User::AccountLoginsController`

      EOM

      tags tag
      security [Bearer: []]
      
      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query

      response '200', 'Doorkeeper::AccessTokens list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/user/account_logins/{id}' do

    delete 'Delete Access Token (logout)' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'account_login'
      description <<~EOM
        Controller: `Api::V1::User::AccountLoginsController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "id", in: :path,
          type: :string,
          required: true,
          description: "Access Token id"

      response '200', 'Doorkeeper::AccessToken deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
