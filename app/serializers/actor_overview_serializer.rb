class ActorOverviewSerializer
  include JSONAPI::Serializer

  set_type :actor

  has_one :map_actor, record_type: :actor, serializer: :actor

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:parent_id) do |record|
    record.parent_id.to_s
  end
  attribute(:parent_ids) do |record|
    record.parent_ids.collect(&:to_s)
  end
  attribute(:map_actor_id) do |record|
    record.map_actor_id.to_s
  end
  attribute(:leaf) do |record|
    record.children_count.to_i.eql?(0)
  end

  attributes(
    :name,
    :actor_type,
    :insertable_child_types,
    :children_count,
    :path,
    :short_name,
    :full_name,
    :active,
    :deleted,
    :created_at,
    :updated_at
  )

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_info', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actor_type, default: 'ou', description: 'type of actor'

          array :insertable_child_types do
            items do
              string :child_type, description: 'the type of actor that is allowed as a child of this actor'
            end
          end

          number :children_count, description: 'number of children below this actor'

          string :path, description: 'the path of this actor within the global tree'
          string :name, default: 'short name', description: 'descriptive name (alphanumeric lowercase) to build a unique path'
          string :short_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :full_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'

          boolean :active, default: true, description: 'indicating if this actor is available'
        end
      }
    end

  end

end
