class RolePickerSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :title,
    :title_translations,
    :description,
    :description_translations,
    :created_at,
    :updated_at
  )

  class Schema < JsonApi::Schema

    def schema_record
      proc do
        string :id, description: 'unique record id'
        string :type, default: 'role', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :name, description: 'unique role name'

          string :title, default: 'title', description: 'a descriptive title (current locale)'
          object :title_translations do
            string :en, description: 'the english locale title'
            string :de, description: 'the german locale title'
          end
          string :description, description: 'a description about what this role allows to do (current locale)'
          object :description_translations, description: 'language keys here are dynamic and can consist of any supported language, minimum should be those languages of the configured app locales' do
            string :en, description: 'the english locale description'
            string :de, description: 'the german locale description'
          end
        end
      end
    end

  end

end
