# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_user_account_activity_index
require 'swagger_helper'

controller = Api::V1::User::AccountActivityController
model = AccountActivity
serializer = AccountActivitySerializer
overview_serializer = AccountActivitySerializer

tag = 'Current User'

describe 'AccountActivities API', swagger_doc: 'v1/swagger.json', "accountactivities" => true  do

  path '/api/v1/user/account_activity' do

    get 'List Account activity' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'account_activity'
      description <<~EOM
        Controller: `Api::V1::User::AccountActivityController`

      EOM

      tags tag
      security [Bearer: []]
      
      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :user_id, :token_id, :ip, :app, :navigator, :location, :device, :_keywords]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :user_id, :token_id, :ip, :app, :navigator, :location, :device, :_keywords]

      response '200', 'AccountActivities list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

  end

  path '/api/v1/user/account_activity' do

    put 'Update Account activity' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'account_activity'
      description <<~EOM
        Controller: `Api::V1::User::AccountActivityController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  required: []
                )

      response '200', 'AccountActivity updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
