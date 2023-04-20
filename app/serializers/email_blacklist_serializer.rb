class EmailBlacklistSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
   :domain,
   :active
  )

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, description: 'record type', default: record_type

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'

          string :domain, description: 'blacklisted domain name'
          string :active, description: 'controls if the domain name is actively being blacklisted'
          string :full_name, description: 'full name'
        end
      }
    end
  end


end