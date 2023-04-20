class TenantUserSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:actor_id) do |record|
    record.actor_id.to_s
  end

  attribute(:tenant_groups) do |record|
    tenant = Actor.tenants.find(record.tenant_context) rescue nil
    tenant.nil? ? [] : tenant.children.groups.where(:id.in => record.actor.determine_actor_ids).pluck(:name)
  end

  attribute(:tenant_group_ids) do |record|
    tenant = Actor.tenants.find(record.tenant_context) rescue nil
    tenant.nil? ? [] : tenant.descendants.groups.where(:id.in => record.actor.determine_actor_ids).pluck(:id).collect(&:to_s)
  end

  attributes(
   :created_at,
   :email,
   :first_name,
   :gender,
   :last_name,
   :short,
   :title,
   :created_at,
   :updated_at,
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
        string :type, default: 'user', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actor_id, description: 'referenced actor id'

          array :tenant_groups, description: 'names of groups the user is member of within the current tenant' do
            items type: :string
          end
          array :tenant_group_ids, description: 'reference ids of groups the user is member of within the current tenant' do
            items type: :string
          end

          string :email, description: 'e-mail address'
          number :gender, description: 'numeric gender 1=male / 2=female / 3+anything'
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
