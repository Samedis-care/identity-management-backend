class TenantSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attributes(
    :actor_type,
    :path,
    :short_name,
    :full_name,
    :modules_available,
    :modules_selected,
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

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_info', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actor_type, default: 'ou', description: 'type of actor'

          array :modules_available, description: 'available optional organization modules' do
            items do
              string :module, description: 'available module name'
            end
          end

          array :modules_selected, default: [], description: 'selected optional organization modules' do
            items do
              string :module, description: 'selected module name'
            end
          end

          string :path, description: 'the path of this actor within the global tree'
          string :short_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :full_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'
        end
      }
    end

  end

end
