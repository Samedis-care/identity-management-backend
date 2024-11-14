class AppUserSerializer
  include JSONAPI::Serializer

  set_type :user

  attribute(:id) do |record|
    record.id.to_s
  end
  attribute(:actor_id) do |record|
    record.actor_id.to_s
  end

  attributes(
   :active,
   :email,
   :unconfirmed_email,
   :recovery_email,
   :unconfirmed_recovery_email,
   :first_name,
   :last_name,
   :gender,
   :locale,
   :short,
   :title,
   :mobile
  )

  attribute :recovered_account do |record|
    !!record.recovered_account
  end

  attribute :image do |user|
    {
      large: user.try(:image_url, :large),
      medium: user.try(:image_url, :medium),
      small: user.try(:image_url, :small)
    }
  end

  # Global candos regardless of tenant.
  # To control things outside of a specific tenant context.
  # Filtered to only supply candos for current app_context
  attribute :candos do |user, params|
    user.global_candos params[:current_app_actor]
  end

  # Filtered to only supply candos for current app_context
  attribute :tenants do |user, params|
    _app = params[:current_app_actor]
    next unless _app

    tenants = user.tenants
    tenants.each do |tenant|
      candos = tenant.symbolize_keys[:candos]
      tenant[:candos] = candos.select { |c| c.start_with?("#{_app.name}/") }
    end
    tenants
  end

  attribute :recent_invite_tokens do |user, params|
    _app = params[:current_app_actor]
    user.recent_invites.where(app: _app.name).pluck(:token).collect &:to_s if _app.present?
  end

  attribute :otp_enabled do |user|
    !!user.otp_enabled?
  end

  attribute :otp_provided do |user, params|
    if user.id.eql? params[:current_user]&.id
      nil
    else
      !!params[:current_token]&.im_otp_provided?
    end
  end

  attribute :otp_provisioning_qr_code do |user, params|
    if user.otp_enable.present? && user.otp_secret_key.present?
      RQRCode::QRCode.new(user.get_provisioning_uri, level: :l).as_svg(
        color: "000",
        use_path: true,
        viewbox: true,
        # svg_attributes: {
        #   #style: "width:20mm; height:20mm"
        # }
      )
    end
  end

  attribute :otp_secret_key do |user, params|
    if user.otp_enable.present?
      user.otp_secret_key
    end
  end

  attribute :otp_backup_codes do |user, params|
    if user.otp_enable.present?
      user.otp_backup_codes || []
    end
  end

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'app_user', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id (of mapping)'
          string :actor_id, description: 'unique id of the users account'
          string :email, description: 'the new e-mail address'
          string :unconfirmed_email, description: 'holds the new email address until it is confirmed'
          string :recovery_email, description: 'a secondary email that can be used to recover an account if access to the main email is lost'
          string :unconfirmed_recovery_email, description: 'holds the chosen recovery email address until it is confirmed'
          boolean :recovered_account, description: 'if true this account was recovered and the main email should be changed'
          string :first_name, default: 'short name of an organizational unit or group', description: 'short name of this actor'
          string :last_name, default: 'full name of an organizational unit or group', description: 'full name of this actor'
          string :short, description: 'User short sign'
          string :title, description: 'User title'
          number :gender, enum: [0, 1, 2], description: <<~EOF
            Gender identifier
            * 0 - Unspecified
            * 1 - Male
            * 2 - Female
          EOF
          string :mobile, description: 'mobile number'
          string :locale, description: 'language code'
          string :current_password, description: 'the current password'
          string :password, description: 'the new password'
          string :password_confirmation, description: 'the new password (confirmation)'
          string :image_b64, description: 'BASE64 encoded image (JPEG or PNG) to be used as the user`s avatar'
          object :image, description: 'image in different sizes' do
            string :large
            string :medium
            string :small
          end
          array :role_ids do
            items do
              string :role_id, description: 'the role id assigned to the user'
            end
          end
          array :tenants do
            items type: :object do
              array :candos do
                items type: :string
              end
            end
          end
          array :recent_invite_tokens, description: 'a list of recent invite tokens to pass to the authenticated remote app so the app can process these' do
            items type: :string
          end
          boolean :otp_enabled, description: 'if true the login needs to present an input for sending an OTP with the login'
          boolean :otp_provided, description: 'if otp_enabled this will be true if an OTP was provided to signal the login is complete'
          string :otp_provisioning_qr_code, description: 'only when enabling OTP/MFA this will show an SVG image with a QR code to scan from an authenticator app'
          string :otp_secret_key, description: 'only when enabling OTP/MFA this will show the secret key to set up an authenticator app'
          array :otp_backup_codes, description: 'only after enabling OTP/MFA this will once show backup codes' do
            items type: :string
          end
        end
      }
    end

  end
end
