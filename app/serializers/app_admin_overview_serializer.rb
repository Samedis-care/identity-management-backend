class AppAdminOverviewSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :name,
    :short_name,
    :full_name,
    :languages,
    :available_languages
  )

  attribute :image do |record|
    {
      large: (record.image[:large].url rescue nil),
      medium: (record.image[:medium].url rescue nil),
      small: (record.image[:small].url rescue nil)
    }
  end


  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_admin', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :name, default: 'app-name', description: 'unique name of the app'
          string :short_name, default: 'app-name', description: 'short name of the app'
          string :full_name, default: 'app-name', description: 'full name of the app'

          array :languages, default: %w(de en), description: 'language codes of configured locales' do
            items do
              string :locale, description: 'language code'
            end
          end
          array :available_languages, default: I18n.available_locales, description: 'language codes of supported locales' do
            items do
              string :locale, description: 'language code'
            end
          end
        end
      }
    end

  end

end
