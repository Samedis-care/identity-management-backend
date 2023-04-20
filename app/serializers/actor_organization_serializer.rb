class ActorOrganizationSerializer
  include JSONAPI::Serializer

  set_type :actor

  has_one :parent, record_type: :actor, serializer: :actor_organization

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:parent_id) do |record|
    record.parent_id.to_s
  end
  attribute(:leaf) do |record|
    record.children_count.to_i.eql?(0)
  end

  attributes(
    :actor_type,
    :insertable_child_types,
    :children_count,
    :path,
    :name,
    :short_name,
    :full_name,
    :title,
    :title_translations,
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
          string :parent_id, description: 'the parent record id'
          boolean :leaf, default: false, description: 'when true this is the last element of a tree'
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

          string :title, default: 'localized title of an organizational unit or group', description: 'short name of this actor'

          object :title_translations do
            string :en, description: 'the english locale'
            string :de, description: 'the german locale'
          end

          boolean :active, default: true, description: 'indicating if this actor is available'
          boolean :deleted, default: false, description: 'indicating if this actor is marked as deleted'

        end
      }
    end

  end

end
