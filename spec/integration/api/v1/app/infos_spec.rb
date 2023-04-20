# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_app_info
require 'swagger_helper'

controller = Api::V1::App::InfosController
model = Actors::App
serializer = AppInfoSerializer
overview_serializer = 

tag = 'App Info'

describe 'Actors::Apps API', swagger_doc: 'v1/swagger.json', "actors::apps" => true  do

  path '/api/v1/app/info/{name}' do

    get 'Loads app info identified by name' do
      metadata[:operation]['x-candos'] = 
      metadata[:operation]['x-record-type'] = 'app_info'
      description <<~EOM
        Controller: `Api::V1::App::InfosController`

      EOM

      tags tag
      security [Bearer: []]
      parameter name: "name", in: :path,
          type: :string,
          required: true,
          description: "App name"

      response '200', 'Actors::App view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

  end

end
