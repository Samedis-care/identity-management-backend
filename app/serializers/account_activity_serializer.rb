class AccountActivitySerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
   :location,
   :device,
   :app,
   :created_at
  )

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, description: 'record type', default: record_type

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :location, description: 'approximated geographic location by ip address that created the token'
          string :device, description: 'user agent that created the token'
          string :app, description: 'app this token belongs to'
          string :created_at, description: 'timestamp when this invite was created'
        end
      }
    end

  end

end