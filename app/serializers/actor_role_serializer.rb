class ActorRoleSerializer
  include JSONAPI::Serializer

  set_type :actor_role

  has_one :actor, record_type: :actor, serializer: :actor_organization

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:actor_id) do |record|
    record.actor_id.to_s
  end
  attribute(:role_id) do |record|
    record.role_id.to_s
  end

  attributes(
    :name,
    :created_at,
    :updated_at
  )

  attribute :title do |record|
    record.role.title
  end

  attribute :description do |record|
    record.role.description
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'actor_role', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actor_id, description: 'the actor id with the assigned role'
          string :role_id, description: 'the role id'
          string :title, description: 'the role title'
          string :description, description: 'the role description'
          string :name, description: 'the role name'
        end
      }
    end

  end

end
