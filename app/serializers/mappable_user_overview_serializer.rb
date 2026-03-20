class MappableUserOverviewSerializer
  include JSONAPI::Serializer

  set_type :mappable_user

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:parent_id) do |record|
    record.parent_id.to_s
  end
  attribute(:parent_ids) do |record|
    record.parent_ids.collect(&:to_s)
  end

  attributes(
    :actor_type,
    :path,
    :short_name,
    :full_name,
    :created_at,
    :updated_at
  )

  attribute :email do |record|
    record.name
  end

  attribute :already_in_orga do |record, params|
    (params[:actor_ids_in_orga]||[]).collect(&:to_s).include?(record.id.to_s)
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_info', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :parent_id, description: 'the parent record id'
          array :parent_ids, description: 'ids of parent actors' do
            items type: :string
          end
          string :actor_type, default: 'ou', description: 'type of actor'

          string :path, description: 'the path of this actor within the global tree'
          string :short_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :full_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'

          string :email, description: 'email address of the associated user'

          boolean :already_in_orga, description: 'Boolean that signals if this actor is already in the orga of the nested resource set'
          string :created_at, format: 'date-time', description: 'created date'
          string :updated_at, format: 'date-time', description: 'updated date'
        end
      }
    end

  end

end
