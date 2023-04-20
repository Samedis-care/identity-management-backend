class ActorTreeSerializer
  include JSONAPI::Serializer

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
    :actor_type,
    :insertable_child_types,
    :children_count,
    :path,
    :name,
    :short_name,
    :full_name,
    :active,
    :deleted,
    :created_at,
    :updated_at
  )

  attribute :image do |record|
    {
      large: (record.image_url(:large) rescue nil),
      medium: (record.image_url(:medium) rescue nil),
      small: (record.image_url(:small) rescue nil)
    }
  end

  class Schema < JsonApi::Schema
    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'actor_tree', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :parent_id, description: 'The id of the actor this new actor will become a children of'
          array :parent_ids, description: 'ids of parent actors' do
            items type: :string
          end
          string :map_actor_id, description: ''
          boolean :leaf, description: ''
          string :actor_type, enum: %w(tenant group ou), default: 'ou', description: 'The type of this actor'
          array :insertable_child_types, description: 'for frontend ruleset only' do
            items do
              string :child_type, description: 'the type of actor that is allowed as a child of this actor'
            end
          end
          number :children_count, description: 'number of the children'
          string :path, description: 'the path of this actor within the global tree'
          string :name, default: 'short name', description: 'descriptive name (alphanumeric lowercase) to build a unique path'
          string :short_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :full_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'
          boolean :active, description: 'flag to check whether actor is active'
          boolean :deleted, description: 'flag to check whether actor is deleted'
          string :created_at, format: 'date-time', description: 'created date'
          string :updated_at, format: 'date-time', description: 'updated date'
          string :image_b64, description: 'BASE64 encoded image (JPEG or PNG) to be used as the user`s avatar'
          object :image, description: 'image with different styles' do
            string :large
            string :medium
            string :small
          end
        end
      }
    end
  end
end
