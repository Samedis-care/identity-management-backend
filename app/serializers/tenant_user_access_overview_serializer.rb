class TenantUserAccessOverviewSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute(:actor_id) do |record|
    record.actor_id.to_s
  end

  attributes(
   :access_group_ids,
   :email,
   :first_name,
   :last_name,
   :title,
   :gender,
   :created_at
  )

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'tenant_user_access_overview', description: 'defines the class of the data'
        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          array :access_group_ids, description: 'id of an access group' do
            items string
          end
          string :actor_id, description: 'unique id of the users account'
          string :email, description: 'registered email address'
          string :first_name, description: 'the users first name'
          string :last_name, description: 'the users last name'
          string :title, null: true, description: 'the users title'
          number :gender, null: true, description: 'the users gender (1=male, 2=female, 3=other)'
          string :created_at, description: 'account creation timestamp'
        end
      }
    end

    def schema_meta
      Proc.new {
        number :total, description: 'number of total records'
        object :json_api_options, &schema_json_api_options
        object :msg, description: 'info about the request', &schema_msg
        # array :access_groups, description: 'meta information to visualize the access a user has' do
        #   items do
        #     object do
        #       string :id, description: 'unique record id'
        #       string :label, description: 'the label of this access group'
        #       string :group, description: 'a grouping name'
        #       string :description, description: 'describes the access this group grants'
        #     end
        #   end
        # end
      }
    end

  end

end
