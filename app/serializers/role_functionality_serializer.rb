class RoleFunctionalitySerializer
  include JSONAPI::Serializer

  set_type :role_functionality

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:role_id) do |record|
    record.role_id.to_s
  end
  attribute(:functionality_id) do |record|
    record.functionality_id.to_s
  end

  attributes(
    :cando,
    :module,
    :ident,
    :created_at,
    :updated_at
  )

  attribute(:title) do |record|
    record.functionality.title
  end

  attribute(:description) do |record|
    record.functionality.title
  end


  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'actor_role', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :role_id, description: 'the role id'
          string :functionality_id, description: 'the actor id with the assigned role'
          string :cando, description: 'the cando'
          string :title, description: 'the functionality title'
          string :description, description: 'the functionality description'
          string :module, description: 'the functionality module'
          string :ident, description: 'the functionality ident'
        end
      }
    end

  end

end
