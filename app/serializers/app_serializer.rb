class AppSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute :url do |record|
    record.config.url || User.host(record.name)
  end

  attributes(
    :name,
    :short_name,
    :full_name,
    :required_documents,
    :requires_acceptance
  )

  attribute :image do |record|
    {
      large: (record.image_url(:large) rescue nil),
      medium: (record.image_url(:medium) rescue nil),
      small: (record.image_url(:small) rescue nil)
    }
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, description: 'record type', default: record_type

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'

          string :name, description: 'unique app name'
          string :short_name, description: 'short name'
          string :full_name, description: 'full name'

          object :required_documents do
            string :name, description: 'name/version of documents to show when logging into this app'
          end
          object :requires_acceptance do
            string :name, description: 'name/boolean of documents that require user acceptance when logging into this app'
          end

          object :image, description: 'image with different styles' do
            string :large
            string :medium
            string :small
          end
        end
      }
    end
  end

end
