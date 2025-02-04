class GroupActorSerializer
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

  attribute(:role_ids) do |record|
    record.role_ids.collect(&:to_s)
  end

  attribute(:map_actor_ids) do |record|
    record.mappings.pluck(:map_actor_id).collect(&:to_s)
  end

  attributes(
    :actor_type,
    :path,
    :name,
    :short_name,
    :full_name,
    :title,
    :title_translations,
    :active,
    :created_at,
    :updated_at
  )

  # # resulting from all actors inherited and mapped
  # attribute :candos do |actor|
  #   actor.determine_candos
  # end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_info', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :parent_id, description: 'the id of the parent actor'
          array :parent_ids, description: 'ids of all ancestor actors' do
            items type: :string
          end

          array :role_ids, description: 'ids of roles assigned to this group' do
            items type: :string
          end

          array :map_actor_ids, description: 'ids of actors mapped into this group' do
            items type: :string
          end

          string :actor_type, enum: %w(tenant group ou), default: 'group', description: 'The type of this actor'

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

          string :created_at, format: 'date-time', description: 'created date'
          string :updated_at, format: 'date-time', description: 'updated date'

        end
      }
    end
  end
end
