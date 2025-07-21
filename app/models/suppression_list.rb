class SuppressionList
  require 'aws-sdk-sesv2'
  require 'aws-sdk-s3'

  def self.recent(since: 1.week.ago)
    raise "Needs Timestamp `since: 1.week.ago`" unless since.is_a?(Time)

    user_ids = Doorkeeper::AccessToken.where(:updated_at.gt => since).distinct(:resource_owner_id)
    emails = User.where(:_id.in => user_ids)
                 .pluck(:email, :email_change, :unconfirmed_email, :recovery_email)
                 .flatten.compact.uniq
    emails |= Invite.where(:created_at.gt => since).pluck(:email)
    emails.compact.uniq.select { it =~ URI::MailTo::EMAIL_REGEXP }
  end

  def self.client
    @client ||= Aws::SESV2::Client.new(
      # note that we use a different region here (due to india)
      region: 'eu-west-1', #ENV['AWS_S3_REGION'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def self.list_all
    next_token = nil
    all_suppressed = []

    loop do
      resp = client.list_suppressed_destinations({
        next_token: next_token
      })

      resp.suppressed_destination_summaries.each do |entry|
        ap entry
        all_suppressed << entry.email_address
      end

      next_token = resp.next_token
    break unless next_token
    end

    all_suppressed
  end

  def self.remove(email)
    raise "INVALID EMAIL TO REMOVE FROM SUPPRESSION LIST" unless email.presence.is_a?(String)

    begin
      client.delete_suppressed_destination(email_address: email)
    rescue Aws::SESV2::Errors::NotFoundException
      # ignore
    end
  end

  def self.cleanup!(since: 1.week.ago)
    # this is very slow as there is a rate limit of 1 req/s enforced
    Parallel.each(recent(since:), progress: 'Only a single address can be removed per second!', in_threads: 1) do |email|
      remove(email)
      sleep 1
    end
  end

  def self.bulk_cleanup!(since: 1.week.ago)
    emails = recent(since:)
    puts "found #{emails.count} recent emails to unsuppress"
    return if emails.empty?

    csv_data = emails.join("\n")

    region = 'eu-west-1' #ENV['AWS_S3_REGION']
    bucket = 'identity-management-ses-bulk-imports' #ENV['AWS_S3_BUCKET']

    puts "setting up S3 client..."
    s3 = Aws::S3::Client.new(
      region:,
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    s3_key = "ses_bulk_remove_from_suppression_list_v3.csv"
    puts "uploading to to s3 >>#{s3_key}<<..."
    s3.put_object(
      bucket:,
      key: s3_key,
      body: csv_data
    )
    s3_url = "s3://#{bucket}/#{s3_key}"

    puts "sending S3 bulk import action for >>#{s3_url}<<..."
    resp = client.create_import_job({
      import_destination: {
        suppression_list_destination: {
          suppression_list_import_action: 'DELETE'
        }
      },
      import_data_source: {
        s3_url:,
        data_format: 'CSV'
      }
    })

    puts "bulk removal started! job id: #{resp.job_id}"
    resp.job_id
  end

end