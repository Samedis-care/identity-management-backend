# Version: 1.0.6
# auto generated test, update via: (append `-f` to force update if needed)
#     rails g auto_swagger_spec v1_email_blacklist_index
require 'swagger_helper'

controller = Api::V1::EmailBlacklistController
model = EmailBlacklist
serializer = EmailBlacklistSerializer
overview_serializer = EmailBlacklistSerializer

tag = 'Email blacklist'

describe 'EmailBlacklists API', swagger_doc: 'v1/swagger.json', "emailblacklists" => true  do

  path '/api/v1/email_blacklist' do

    get 'List Email blacklist' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/email-blacklists.reader"]
      metadata[:operation]['x-record-type'] = 'email_blacklist'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/email-blacklists.reader
        ---
        Controller: `Api::V1::EmailBlacklistController`

      EOM

      tags tag
      security [Bearer: []]
      
      include_examples :paging
      include_examples :quickfilter
      include_examples :sorting, :query
      include_examples :gridfilter, :query, [:_id, :created_at, :updated_at, :domain, :active, :_keywords]
      metadata[:operation]['x-gridfilter-fields'] = [:_id, :created_at, :updated_at, :domain, :active, :_keywords]

      response '200', 'EmailBlacklists list' do
        schema overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true
        run_test!
      end
    end

    post 'Create Email blacklist' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/email-blacklists.writer"]
      metadata[:operation]['x-record-type'] = 'email_blacklist'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/email-blacklists.writer
        ---
        Controller: `Api::V1::EmailBlacklistController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  #required: []
                )

      response '200', 'EmailBlacklist created' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

  path '/api/v1/email_blacklist' do

    get 'Show Email blacklist' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/email-blacklists.reader"]
      metadata[:operation]['x-record-type'] = 'email_blacklist'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/email-blacklists.reader
        ---
        Controller: `Api::V1::EmailBlacklistController`

      EOM

      tags tag
      security [Bearer: []]
      
      response '200', 'EmailBlacklist view' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    put 'Update Email blacklist' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/email-blacklists.writer"]
      metadata[:operation]['x-record-type'] = 'email_blacklist'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/email-blacklists.writer
        ---
        Controller: `Api::V1::EmailBlacklistController`

      EOM

      tags tag
      security [Bearer: []]
      
      parameter name: :data, in: :body,
                schema: serializer::Schema.new.rswag_schema(
                  base_key: :data,
                  only: [],
                  required: []
                )

      response '200', 'EmailBlacklist updated' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end

    delete 'Delete Email blacklist' do
      metadata[:operation]['x-candos'] = ["identity-management/global.admin+identity-management/email-blacklists.deleter"]
      metadata[:operation]['x-record-type'] = 'email_blacklist'
      description <<~EOM
        To use this endpoint the current user needs to be authorized for the tenant to do any of these
        - identity-management/global.admin+identity-management/email-blacklists.deleter
        ---
        Controller: `Api::V1::EmailBlacklistController`

      EOM

      tags tag
      security [Bearer: []]
      
      response '200', 'EmailBlacklist deleted' do
        schema serializer::Schema.new.swagger_schema single: true, meta: true, links: true
        run_test!
      end
    end
  end

end
