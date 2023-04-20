class AccountLoginSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute(:current) do |record, params|
    record.token.eql? params[:bearer_token]
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
          string :location, description: 'approximated geographic location by ip address that created the token'
          string :device, description: 'user agent that created the token'
          string :app, description: 'app this token belongs to'
          boolean :otp_required, description: 'true if this token requires to be verified by an OTP'
          boolean :otp_provided, description: 'true if the user has provided an OTP'
        end
      }
    end

  end

end