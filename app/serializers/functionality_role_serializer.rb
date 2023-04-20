class FunctionalityRoleSerializer
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
  attribute(:title) do |record, params|
    params.dig(:roles, record.role_id).title
  end
  attribute(:description) do |record, params|
    params.dig(:roles, record.role_id).title
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'actor_role', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :role_id, description: 'the role id'
          string :functionality_id, description: 'the functionality id'
          string :title, description: 'the role title'
          string :description, description: 'the role description'
        end
      }
    end

  end

end
