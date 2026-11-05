require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2658: this controller listed
# ~/invites.{reader,writer,deleter} for index/create/destroy, but its only route is the
# accept PUT. Those checks could never run, and they were the last code reference keeping
# the invites.* candos looking live next to the invitations.* ones that are.
RSpec.describe Api::V1::User::InvitationsController, type: :controller do
  it 'serves only the accept action' do
    expect(described_class.action_methods.to_a & %w[index show create update destroy]).to eq(%w[update])
  end

  it 'lists candos only for the action it serves' do
    expect(controller.send(:cando)).to eq(update: %w[public])
  end

  describe 'routing', type: :routing do
    it 'routes the accept PUT here' do
      expect(put: '/api/v1/user/invitations/abc123')
        .to route_to(controller: 'api/v1/user/invitations', action: 'update', id: 'abc123', noswagger: true)
    end

    it 'routes no DELETE here' do
      expect(delete: '/api/v1/user/invitations/abc123').not_to be_routable
    end
  end
end
