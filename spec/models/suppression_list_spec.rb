require 'rails_helper'

# SES drops every mail to an address after a hard bounce. Invites are often sent before the
# invitee's mailbox exists, so Invite#after_create lifts the suppression again - but only
# for BOUNCE, a COMPLAINT must stay suppressed.
RSpec.describe SuppressionList do
  let(:ses) { instance_double(Aws::SESV2::Client) }
  let(:email) { 'someone@suppression-spec.test' }

  def entry(reason)
    Aws::SESV2::Types::GetSuppressedDestinationResponse.new(
      suppressed_destination: Aws::SESV2::Types::SuppressedDestination.new(
        email_address: email, reason: reason, last_update_time: Time.now
      )
    )
  end

  before do
    allow(described_class).to receive(:enabled?).and_return(true)
    allow(described_class).to receive(:client).and_return(ses)
  end

  describe '.release_bounced' do
    it 'removes an address suppressed because of a bounce' do
      allow(ses).to receive(:get_suppressed_destination).with(email_address: email).and_return(entry('BOUNCE'))
      expect(ses).to receive(:delete_suppressed_destination).with(email_address: email)

      expect(described_class.release_bounced(email)).to be(true)
    end

    it 'normalizes the address before asking SES' do
      allow(ses).to receive(:get_suppressed_destination).with(email_address: email).and_return(entry('BOUNCE'))
      expect(ses).to receive(:delete_suppressed_destination).with(email_address: email)

      described_class.release_bounced("  #{email.upcase} ")
    end

    it 'keeps an address suppressed because of a complaint' do
      allow(ses).to receive(:get_suppressed_destination).and_return(entry('COMPLAINT'))
      expect(ses).not_to receive(:delete_suppressed_destination)

      expect(described_class.release_bounced(email)).to be(false)
    end

    it 'does nothing for an address that is not suppressed' do
      allow(ses).to receive(:get_suppressed_destination)
        .and_raise(Aws::SESV2::Errors::NotFoundException.new(nil, 'not found'))
      expect(ses).not_to receive(:delete_suppressed_destination)

      expect(described_class.release_bounced(email)).to be(false)
    end

    it 'does not raise but reports to Sentry when SES fails' do
      allow(ses).to receive(:get_suppressed_destination)
        .and_raise(Aws::SESV2::Errors::TooManyRequestsException.new(nil, 'slow down'))
      expect(Sentry).to receive(:capture_exception)

      expect(described_class.release_bounced(email)).to be(false)
    end

    it 'ignores blank and malformed addresses without calling SES' do
      expect(ses).not_to receive(:get_suppressed_destination)

      expect(described_class.release_bounced(nil)).to be(false)
      expect(described_class.release_bounced('not an email')).to be(false)
    end

    it 'does nothing without SES credentials' do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(ses).not_to receive(:get_suppressed_destination)

      expect(described_class.release_bounced(email)).to be(false)
    end
  end

  describe '.bulk_release_bounced!' do
    let(:s3) { instance_double(Aws::S3::Client, put_object: true) }

    def page(*emails, next_token: nil)
      Aws::SESV2::Types::ListSuppressedDestinationsResponse.new(
        suppressed_destination_summaries: emails.map { |e| Aws::SESV2::Types::SuppressedDestinationSummary.new(email_address: e) },
        next_token: next_token
      )
    end

    before { allow(Aws::S3::Client).to receive(:new).and_return(s3) }

    it 'imports all bounced addresses as DELETE job and never asks for complaints to be removed' do
      allow(ses).to receive(:list_suppressed_destinations)
        .with(reasons: ['BOUNCE'], next_token: nil).and_return(page('a@x.test', next_token: 'n2'))
      allow(ses).to receive(:list_suppressed_destinations)
        .with(reasons: ['BOUNCE'], next_token: 'n2').and_return(page('b@x.test'))
      allow(ses).to receive(:list_suppressed_destinations)
        .with(reasons: ['COMPLAINT'], next_token: nil).and_return(page('c@x.test'))
      allow(ses).to receive(:create_import_job).and_return(double(job_id: 'job-1'))

      expect(described_class.bulk_release_bounced!).to eq('job-1')
      expect(s3).to have_received(:put_object).with(hash_including(body: "a@x.test\nb@x.test"))
      expect(ses).to have_received(:create_import_job)
        .with(hash_including(import_destination: { suppression_list_destination: { suppression_list_import_action: 'DELETE' } }))
    end

    it 'does nothing when no address is suppressed because of a bounce' do
      allow(ses).to receive(:list_suppressed_destinations).and_return(page)
      allow(ses).to receive(:create_import_job)

      expect(described_class.bulk_release_bounced!).to be_nil
      expect(ses).not_to have_received(:create_import_job)
    end
  end

  describe 'Invite creation' do
    let(:sfx) { SecureRandom.hex(4) }
    let!(:tenant) { Actors::Tenant.create!(name: "t#{sfx}") }

    after do
      Invite.where(email: email).delete_all
      tenant.delete
    end

    it 'lifts a bounce suppression for the invited address' do
      expect(described_class).to receive(:release_bounced).with(email)

      Invite.create!(email: email, invitable_type: 'tenant', tenant: tenant)
    end

    it 'still creates the invite when SES is unreachable' do
      allow(ses).to receive(:get_suppressed_destination).and_raise(Seahorse::Client::NetworkingError.new(StandardError.new('down')))
      allow(Sentry).to receive(:capture_exception)

      expect { Invite.create!(email: email, invitable_type: 'tenant', tenant: tenant) }
        .to change { Invite.where(email: email).count }.by(1)
    end
  end
end
