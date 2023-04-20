class PickerFunctionalityRoleSerializer
  include JSONAPI::Serializer

  has_many :functionalities, record_type: :functionality, serializer: FunctionalityOverviewSerializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :title,
    :title_translations,
    :description,
    :description_translations,
    :app,
    :name,
    :created_at,
    :updated_at
  )
  attribute(:functionality_ids) {|record| record.functionality_ids.collect(&:to_s) }

  attribute :already_in_functionality do |record, params|
    (params[:role_ids_in_functionality]||[]).collect(&:to_s).include?(record.id.to_s)
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
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

          string :app, default: 'app-name', description: 'name of app this role belongs to'

          array :functionality_ids do
            items do
              string :id, description: 'id of a functionality assigned to this role'
            end
          end

        end
      }
    end

  end

end
