class PickerRoleFunctionalitySerializer
  include JSONAPI::Serializer

  has_many :roles, record_type: :role, serializer: RoleOverviewSerializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute(:role_ids) do |record|
    record.role_ids.collect &:to_s
  end

  attributes(
    :title,
    :title_translations,
    :description,
    :description_translations,
    :app,
    :module,
    :ident,
    :created_at,
    :updated_at)

  attribute :already_in_role do |record, params|
    (params[:functionality_ids_in_role]||[]).collect(&:to_s).include?(record.id.to_s)
  end

  class Schema < JsonApi::Schema
    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'functionality', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :title, default: 'title', description: 'a descriptive title (current locale)'
          object :title_translations do
            string :en, description: 'the english locale title'
            string :de, description: 'the german locale title'
          end
          string :description, description: 'a description about what this functionality allows to do (current locale)'
          object :description_translations, description: 'language keys here are dynamic and can consist of any supported language, minimum should be those languages of the configured app locales' do
            string :en, description: 'the english locale description'
            string :de, description: 'the german locale description'
          end
          string :app, default: 'app-name', description: 'name of app this functionality belongs to'
          string :module, default: 'module', description: 'the module of the app this functionality belongs to'
          string :ident, default: 'ident', description: 'the action within the module (e.g. reader, writer, deleter, consumer, ...)'

          array :role_ids do
            items do
              string :id, description: 'id of a role'
            end
          end
        end
      }
    end
  end
end
