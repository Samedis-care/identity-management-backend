class MappingSerializer
  include JSONAPI::Serializer

  #has_one :parent, record_type: :actor, serializer: :actor
  #has_one :map_actor, record_type: :actor, serializer: :actor

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
    :short_name,
    :path,
    :created_at,
    :updated_at
  )

  class Schema < JsonApi::Schema
    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'mapping', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :parent_id, description: 'id of the parent node'
          string :map_actor_id, description: 'id of the actor that is mapped into the parent node'
          string :short_name, description: 'the friendly name of the mapped actor (e.g. Users name )'
          string :path, description: 'complete path within the hierarchical structure'
        end
      }
    end
  end
end
