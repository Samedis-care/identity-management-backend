class RoleOverviewSerializer
  include JSONAPI::Serializer

  set_type :role

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :title,
    :description,
    :app,
    :name,
    :created_at,
    :updated_at
  )

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'role', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :title, default: 'title', description: 'a descriptive title'
          string :description, default: 'description', description: 'a description about what this role allows to do'
          string :app, default: 'app-name', description: 'name of app this role belongs to'
        end
      }
    end

  end

end
