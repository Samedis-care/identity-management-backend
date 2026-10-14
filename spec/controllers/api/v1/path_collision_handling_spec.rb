require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3160: an Actor::PathCollisionError
# raised while renaming/deleting an actor used to reach the client as the generic
# "Datenbankfehler" (500). It is now a 409 with its own message, still reported to Sentry with
# the collisions. The rename/delete itself is already persisted when this is raised
# (rebuild_path! is an after_save), so the message must not suggest that nothing was saved.
RSpec.describe BaseControllerMethods, 'Actor::PathCollisionError handling' do
  subject(:controller_instance) { Api::V1::EmailBlacklistController.new }

  let(:collisions) { [{ path: 'tenant / someone@x.test', actor_ids: %w[a b] }] }
  let(:error) { Actor::PathCollisionError.new('collision', collisions: collisions) }

  before do
    allow(controller_instance).to receive_messages(render_jsonapi_error: nil, silence_errors?: true, performed?: false)
    allow(Sentry).to receive(:capture_exception)
  end

  it 'is handled by its own rescue_from, not the generic Exception handler' do
    controller_instance.rescue_with_handler(error)

    expect(controller_instance).to have_received(:render_jsonapi_error)
      .with(anything, 'path_collision_error', 409, exception: error)
  end

  it 'reports the collisions to Sentry' do
    controller_instance.rescue_with_handler(error)

    expect(Sentry).to have_received(:capture_exception).with(error, extra: { collisions: collisions })
  end

  it 'uses the localized message in production' do
    allow(Rails.env).to receive(:production?).and_return(true)
    controller_instance.rescue_with_handler(error)

    expect(controller_instance).to have_received(:render_jsonapi_error)
      .with(I18n.t('json_api.path_collision_error'), anything, anything, anything)
  end

  describe 'the translations' do
    let(:messages) { %i[en de fr nl ru].index_with { |locale| I18n.t('json_api.path_collision_error', locale: locale, default: nil) } }

    it 'exist in every locale' do
      expect(messages.values).to all(be_present)
    end

    it 'are distinct per locale' do
      expect(messages.values.uniq.size).to eq(5)
    end

    it 'say the change was saved (en), so nobody saves again believing it was rejected' do
      expect(messages[:en]).to match(/was saved/i)
    end
  end
end
