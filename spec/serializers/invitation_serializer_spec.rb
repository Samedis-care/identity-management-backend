require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2811: InvitationSerializer
# documented email/user_id as write_only request attributes but exposed no way to read
# back valid_until (permitted as a request field since #2810) or target_url. A caller
# creating an invite had no way to see the effective expiry - including the 2-year clamp
# #2810 introduced, or the 30-day default when none was supplied.
RSpec.describe InvitationSerializer, type: :model do
  let(:sfx) { SecureRandom.hex(4) }
  let!(:tenant) { Actors::Tenant.create!(name: "t#{sfx}") }

  let!(:invite) do
    Invite.create!(
      email: "invite-#{sfx}@invite-spec.test",
      tenant: tenant,
      invitable_type: 'tenant',
      invitable_id: tenant.id.to_s,
      auto_accept: true,
      valid_until: 1.year.from_now,
      target_url: 'https://example.test/welcome'
    )
  end

  after { invite.destroy }

  # The `url` attribute (unrelated to this spec) calls a route helper, which requires
  # Devise.secret_key to be configured - stub it so this spec stays hermetic regardless
  # of that local/CI config detail.
  before do
    allow(Rails.application.routes.url_helpers).to receive(:v1_user_invitation_accept_url)
      .and_return('https://ident.example.test/accept')
  end

  it 'exposes valid_until so a caller can read back the effective expiry' do
    attrs = described_class.new(invite).serializable_hash[:data][:attributes]

    expect(Time.zone.parse(attrs[:valid_until]).to_i).to be_within(1.minute).of(1.year.from_now.to_i)
  end

  it 'exposes target_url' do
    attrs = described_class.new(invite).serializable_hash[:data][:attributes]

    expect(attrs[:target_url]).to eq('https://example.test/welcome')
  end
end
