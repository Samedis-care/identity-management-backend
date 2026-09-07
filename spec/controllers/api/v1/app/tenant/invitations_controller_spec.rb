require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#2810: params_create used to
# silently strip a caller-supplied valid_until via strong params, so every invite created
# through this endpoint (e.g. samedis-care-backend's Staff#process_auto_join!, which sends
# 1.year.from_now) fell back to Invite.expire_time = 30.days.from_now no matter what the
# caller asked for.
RSpec.describe Api::V1::App::Tenant::InvitationsController, type: :controller do
  describe '#params_create' do
    it 'permits valid_until instead of silently dropping it' do
      raw = ActionController::Parameters.new(
        data: {
          email: 'someone@invite-spec.test',
          invitable_type: 'tenant',
          invitable_id: 'irrelevant-for-this-check',
          auto_accept: true,
          valid_until: 1.year.from_now.iso8601
        }
      )
      allow(controller).to receive(:params).and_return(raw)

      permitted = controller.send(:params_create)

      expect(permitted[:valid_until]).to be_present
    end
  end
end
