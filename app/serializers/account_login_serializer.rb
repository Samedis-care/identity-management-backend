class AccountLoginSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute(:current) do |record, params|
    record.token.eql? params[:bearer_token]
  end

  # false for a token soft-killed by logout (Api::V1::Doorkeeper::TokensController
  # #revoke writes expires_in: -1 for the token_type_hint: 'access_token' branch) or
  # naturally aged past its own expires_in. #index now lists both active and
  # soft-killed-but-unrevoked tokens (#2495) so the surviving refresh_token on the
  # latter stays reachable for deletion from another device; this is what tells the
  # UI apart which is which, so a logged-out session doesn't read as an active one
  # (the #2422 gap #index used to have).
  attribute(:active) do |record|
    !record.expired?
  end

  attribute(:location) do |record|
    record.im_location.to_s
  end
  attribute(:device) do |record|
    record.im_device.to_s
  end
  attribute(:app) do |record|
    record.im_app.to_s
  end

  attributes(
   :created_at
  )

  attribute :otp_required do |record|
    !!record.im_otp_required?
  end

  attribute :otp_provided do |record|
    !!record.im_otp_provided?
  end


  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, description: 'record type', default: record_type

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          boolean :current, description: 'true if this is the currently used token'
          boolean :active, description: "false once this session's own access-token window has closed " \
            '(logout writes expires_in: -1, or natural expiry); its refresh token may still be valid ' \
            'and usable to sign back in without password/MFA'
          string :location, description: 'approximated geographic location by ip address that created the token'
          string :device, description: 'user agent that created the token'
          string :app, description: 'app this token belongs to'
          boolean :otp_required, description: 'true if this token requires to be verified by an OTP'
          boolean :otp_provided, description: 'true if the user has provided an OTP'
          string :created_at, format: 'date-time', description: 'created date'
        end
      }
    end

  end

end