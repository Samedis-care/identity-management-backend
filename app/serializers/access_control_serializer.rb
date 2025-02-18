class AccessControlSerializer
  include JSONAPI::Serializer

  attributes(:id, :name, :group, :group_name, :label)
  attribute :description do |record|
    [record.description].flatten.join("\n")
  end

  attribute :role_ids do |record|
    record.role_ids.collect(&:to_s)
  end

  class Schema < JsonApi::Schema

    def schema_record
      proc do
        string :id, description: 'unique record id'
        string :type, description: 'record type', default: record_type
        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :label, description: 'the label of this access group'
          string :group, description: 'a grouping name'
          string :description, description: 'describes the access this group grants (Markdown)'

          array :role_ids do
            items do
              string :role_id, description: 'Id of a roles assigned to this access group'
            end
          end
        end
      end
    end

  end

end
