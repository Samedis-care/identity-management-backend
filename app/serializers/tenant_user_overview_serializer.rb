class TenantUserOverviewSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:actor_id) do |record|
    record.actor_id.to_s
  end

  attributes(
   :active,
   :email,
   :gender,
   :first_name,
   :last_name,
   :short,
   :title,
   :created_at,
   :updated_at)

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
        string :type, default: 'user', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actor_id, description: 'referenced actor id'
          string :email, description: 'e-mail address'
          number :gender, enum: [0, 1, 2], description: <<~EOF
            Gender identifier
            * 0 - Unspecified
            * 1 - Male
            * 2 - Female
          EOF
          string :first_name, description: 'first name'
          string :last_name, description: 'last name'
          string :short, description: 'short name (combination of first and last names)'
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
