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

  # SES puts an address on the account-level suppression list after a hard bounce. For invites
  # that is a trap: customers often invite someone before their IT has created the mailbox,
  # the first mail bounces ("550 No such user") and every later invite is then silently dropped.
  #
  # Lifts the suppression so the next mail is attempted again, but ONLY for reason BOUNCE.
  # COMPLAINT (the recipient marked us as spam) stays suppressed.
  # Never raises: it runs while an invite is created and must not break that.
  # Returns true only if the address was removed from the list.
  def self.release_bounced(email)
    return false unless enabled?

    email = email.to_s.strip.downcase
    return false unless email =~ URI::MailTo::EMAIL_REGEXP

    entry = client.get_suppressed_destination(email_address: email).suppressed_destination
    return false unless entry&.reason.to_s.upcase == 'BOUNCE'

    client.delete_suppressed_destination(email_address: email)
    true
  rescue Aws::SESV2::Errors::NotFoundException
    false # not suppressed, the usual case
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { context: 'SuppressionList.release_bounced' })
    false
  end

  # without SES credentials (on-prem, dev) there is nothing to release. Never in the test env:
  # a developer's config/application.yml may hold real keys, and every Invite.create in the
  # suite would then call the real SES account.
  def self.enabled?
    return false if Rails.env.test?

    ENV['AWS_ACCESS_KEY_ID'].present? && ENV['AWS_SECRET_ACCESS_KEY'].present?
  end

  # All addresses SES suppressed for the given reasons (BOUNCE and/or COMPLAINT), without the
  # debug output of .list_all
  def self.list_by_reason(*reasons)
    reasons = reasons.flatten.map { it.to_s.upcase }
    next_token = nil
    emails = []

    loop do
      resp = client.list_suppressed_destinations(reasons: reasons, next_token: next_token)
      emails.concat(resp.suppressed_destination_summaries.map(&:email_address))
      next_token = resp.next_token
      break unless next_token
    end

    emails
  end

  # Takes EVERY address with reason BOUNCE off the suppression list in one SES import job
  # (one request per second would take hours for a long list). COMPLAINT entries are never
  # touched. Returns the job id, or nil if there was nothing to remove.
  def self.bulk_release_bounced!
    emails = list_by_reason('BOUNCE')
    puts "found #{emails.count} bounced addresses (#{list_by_reason('COMPLAINT').count} complaints stay suppressed)"
    return if emails.empty?

    region = 'eu-west-1' # same as .client
    bucket = 'identity-management-ses-bulk-imports'
    s3_key = "ses_bulk_release_bounced_#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}.csv"

    s3 = Aws::S3::Client.new(
      region:,
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )
    puts "uploading to s3 >>#{s3_key}<<..."
    s3.put_object(bucket:, key: s3_key, body: emails.join("\n"))

    resp = client.create_import_job(
      import_destination: { suppression_list_destination: { suppression_list_import_action: 'DELETE' } },
      import_data_source: { s3_url: "s3://#{bucket}/#{s3_key}", data_format: 'CSV' }
    )
    puts "bulk removal started! job id: #{resp.job_id}"
    resp.job_id
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