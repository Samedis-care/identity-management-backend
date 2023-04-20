class FunctionalityOverviewSerializer
  include JSONAPI::Serializer

  set_type :functionality

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute :role_ids do |record|
    record.role_ids.collect &:to_s
  end

  attributes(
   :title,
   :description,
   :app,
   :module,
   :ident,
   :created_at,
   :updated_at)

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'functionality', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          array :role_ids do
            items do
              string :id, description: 'id of a role'
            end
          end
          string :title, default: 'title', description: 'a descriptive title'
          string :description, default: 'description', description: 'a description about what this functionality allows to do'
          string :app, default: 'app-name', description: 'name of app this functionality belongs to'
          string :module, default: 'module', description: 'the module of the app this functionality belongs to'
          string :ident, default: 'ident', description: 'the action within the module (e.g. reader, writer, deleter, consumer, ...)'
        end
      }
    end

  end

end
