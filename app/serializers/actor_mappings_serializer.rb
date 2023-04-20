class ActorMappingsSerializer
  include JSONAPI::Serializer

  has_one :parent, record_type: :actor, serializer: :actor
  has_one :map_actor, record_type: :actor, serializer: :actor

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:parent_id) do |record|
    record.parent_id.to_s
  end
  attribute(:map_actor_id) do |record|
    record.map_actor_id.to_s
  end

  attributes(
    :name,
    :actor_type,
    :short_name,
    :full_name,
    :path,
    :active,
    :mapped,
    :created_at,
    :updated_at
  )
  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, description: 'record type', default: record_type

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :parent_id, description: 'The id of the actor this new actor will become a children of'
          string :map_actor_id, description: ''

          string :name, default: 'short name', description: 'descriptive name (alphanumeric lowercase) to build a unique path'
          string :short_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :full_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'
          string :path, description: 'the path of this actor within the global tree'
          boolean :active, default: true, description: 'indicating if this actor is available'
          boolean :mapped, description: 'true if already mapped into the parent, when false this record cannot be selected'
          string :created_at, format: 'date-time', description: 'created date'
          string :updated_at, format: 'date-time', description: 'updated date'
        end
      }
    end
  end


end
