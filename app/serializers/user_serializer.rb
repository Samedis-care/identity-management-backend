class UserSerializer
  include JSONAPI::Serializer

  belongs_to :actor, record_type: :actor, serializer: :actor_overview
  has_many :tenants, record_type: :actor, serializer: :actor_overview do |user|
    Actor.tenants.where(:id.in => user.actor.actor_ids)
  end
  has_many :groups, record_type: :actor, serializer: :actor_overview do |user|
    Actor.groups.where(:id.in => user.actor.actor_ids)
  end

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:actor_id) do |record|
    record.actor_id.to_s
  end

  attributes(
    :active,
    :deleted,
    :email,
    :title,
    :first_name,
    :last_name,
    :short,
    :gender,
    :invalidate,
    :invalid_at,
    :mobile,
    :locale,
    :pwd_reset_uid,
    :first_login_at,
    :last_login_at,
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

  # resulting from all actors inherited and mapped
  attribute :candos do |user|
    user.global_candos
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
          string :title, description: 'an optional user title'
          string :mobile, description: 'mobile number'

          boolean :active, description: 'if set false the login will be disabled'
          boolean :invalidate, description: 'returns true if an invalid_at date is present'
          string :invalid_at, format: 'date-time', description: 'if set the login will be disabled after the date'
          string :locale, description: 'serves as languange preference for the user'
          string :pwd_reset_uid, description: 'in case of a password reset this serves as a substitute for the old password'
          string :first_login_at, format: 'date-time', description: 'first login date'
          string :last_login_at, format: 'date-time', description: 'last login date'

          array :candos, description: 'global candos the user has consolidated over all tenants' do
            items type: :string
          end

          string :created_at, format: 'date-time', description: 'created date'
          string :updated_at, format: 'date-time', description: 'updated date'
        end
      }
    end

  end

end
