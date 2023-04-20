class ContentSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :app,
    :name,
    :version,
    :content_translations,
    :active,
    :acceptance_required,
    :created_at,
    :updated_at)

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'content', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actors_app_id, description: 'id of the app this content belongs to'
          string :name, default: 'app-info', enum: Content.enumerized_attributes[:name].values, description: 'name of the content (like "tos", "app-info")'
          number :version, description: 'highest active-flagged version will be used'
          object :content_translations, description: 'Hash of locale-languages with translated content' do
            string :de, default: 'Deutsche Übersetzung', description: 'German content'
            string :en, default: 'English translation', description: 'English content'
          end
          boolean :active, default: false, description: 'only active flagged will be used, leave inactive during draft'
          boolean :acceptance_required, default: false, description: 'when true the user is required to accept every new version of this content'
        end
      }
    end

  end

end
