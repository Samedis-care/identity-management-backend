class InvitationSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute :url do |record|
    Rails.application.routes.url_helpers.invitation_accept_url(id: record.token)
  end

  attribute :redirect_url do |record|
    record.target_url ? record.target_url : "#{User.host(record.app)}"
  end

  attributes(
    :invitable_type,
    :invitable_id,
    :actions,
    :token,
    :app,
    :token,
    :tenant_id,
    :auto_accept,
    :accepted_at,
    :done,
    :has_account,
    :created_at,
    :updated_at
  )

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'invitation', description: 'defines the class of the data'
        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :email, description: 'e-mail of the user to invite'
          string :user_id, description: 'Optionally the user id instead of email user to invite'
          string :invitable_type, default: 'tenant', description: 'the object class this invitation refers to'
          string :invitable_id, description: 'the id of the object this invitation refers to'
          object :actions, description: 'JSON Hash with key value pairs of one or more actions (key) to run on accept with arguments (value)' do
            array :access_group_ids, description: 'ids to the groups below a tenant organization to authorize the user acception invites (removes all previous)'
            array :access_groups, description: 'name identifiers in the form of `ou-name/group-name` to the groups below a tenant organization to authorize the user acception invites (removes all previous)'
            array :add_access_group_ids, description: 'ids to the groups below a tenant organization to authorize the user acception invites (adds to those the user already has)'
            array :add_access_groups, description: 'name identifiers in the form of `ou-name/group-name` to the groups below a tenant organization to authorize the user acception invites (adds to those the user already has)'
          end
          string :app, description: 'the app context'
          string :token, description: 'a unique token id that the server generates'
          string :tenant_id, description: 'the used as tenant context'
          boolean :auto_accept, default: true, description: 'automatically performs the invitation as soon as the user is logging in'
          string :url, description: 'the URL to be used to log in to accept the invitation'
          string :redirect_url, description: 'after the invitation was accepted the user will be redirect to this url'
          string :accepted_at, format:'date-time', description: 'timestamp if/when the invitation was accepted'
          boolean :done, default: false, description: 'indicating if this invitation is outstanding'
          string :created_at, format:'date-time', description: 'timestamp when the invitation was created'
          string :updated_at, format:'date-time', description: 'timestamp when the invitation was updated'
        end
      }
    end

    def schema_meta
      Proc.new {
        number :total, description: 'number of total records'
        object :json_api_options, &schema_json_api_options
        object :msg, description: 'info about the request', &schema_msg
        array :access_groups, description: 'meta information to visualize the access a user has' do
          items do
            object do
              string :id, description: 'unique record id'
              string :label, description: 'the label of this access group'
              string :group, description: 'a grouping name'
              string :description, description: 'describes the access this group grants'
            end
          end
        end
      }
    end

  end

end
