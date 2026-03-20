class PickerRoleActorSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:parent_id) do |record|
    record.parent_id.to_s
  end

  attributes(
    :actor_type,
    :children_count,
    :path,
    :short_name,
    :full_name,
    :title,
    :title_translations,
    :active,
    :created_at,
    :updated_at
  )

  attribute :image do |record|
    {
      large: (record.image[:large].url rescue nil),
      medium: (record.image[:medium].url rescue nil),
      small: (record.image[:small].url rescue nil)
    }
  end

  attribute :already_in_role do |record, params|
    (params[:actor_ids_in_role]||[]).collect(&:to_s).include?(record.id.to_s)
  end

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
          string :parent_id, description: 'the parent record id'
          string :actor_type, default: 'ou', description: 'type of actor'

          number :children_count, description: 'number of children below this actor'

          string :path, description: 'the path of this actor within the global tree'
          string :short_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :full_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'

          string :title, default: 'localized title of an organizational unit or group', description: 'short name of this actor'

          object :title_translations do
            string :en, description: 'the english locale'
            string :de, description: 'the german locale'
          end

          boolean :already_in_role, description: 'Boolean that signals if this actor is already in the role of the nested resource set'

          boolean :active, default: true, description: 'indicating if this actor is available'
          object :image, description: 'image in different sizes' do
            string :large
            string :medium
            string :small
          end
          string :created_at, format: 'date-time', description: 'created date'
          string :updated_at, format: 'date-time', description: 'updated date'
        end
      }
    end

  end

end
