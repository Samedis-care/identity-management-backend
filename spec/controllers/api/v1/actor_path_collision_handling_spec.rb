require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3160: an Actor::PathCollisionError
# raised while renaming/deleting an actor used to reach the client as the generic
# "Datenbankfehler" (500). It is now a 409 that names the colliding ids and is still reported
# to Sentry with them.
RSpec.describe BaseControllerMethods, 'Actor::PathCollisionError handling' do
  subject(:controller_instance) { Api::V1::EmailBlacklistController.new }

  let(:ids) { [BSON::ObjectId.new, BSON::ObjectId.new] }
  let(:error) { Actor::PathCollisionError.new(name: 'someone@x.test', path: 'tenant / someone@x.test', actor_ids: ids) }
  let(:scope) { instance_double(Sentry::Scope, set_context: nil) }

  before do
    allow(controller_instance).to receive_messages(render_jsonapi_error: nil, silence_errors?: true, performed?: false)
    allow(Sentry).to receive(:with_scope).and_yield(scope)
    allow(Sentry).to receive(:capture_exception)
  end

  it 'is handled by its own rescue_from, not the generic Exception handler' do
    controller_instance.rescue_with_handler(error)

    expect(controller_instance).to have_received(:render_jsonapi_error)
      .with(anything, 'actor_path_collision', 409, hash_including(meta: { actor_ids: ids.map(&:to_s) }))
  end

  it 'reports the colliding ids to Sentry' do
    controller_instance.rescue_with_handler(error)

    expect(scope).to have_received(:set_context)
      .with('actor_path_collision', hash_including(path: 'tenant / someone@x.test', actor_ids: ids.map(&:to_s)))
    expect(Sentry).to have_received(:capture_exception).with(error)
  end

  it 'names the ids in the localized production message' do
    allow(Rails.env).to receive(:production?).and_return(true)
    controller_instance.rescue_with_handler(error)

    expect(controller_instance).to have_received(:render_jsonapi_error)
      .with(a_string_including(ids.first.to_s, ids.last.to_s), anything, anything, anything)
  end

  %i[en de fr nl ru].each do |locale|
    it "has a #{locale} translation that interpolates the ids" do
      message = I18n.t('json_api.actor_path_collision_error', ids: 'abc, def', locale: locale, default: nil)

      expect(message).to include('abc, def')
    end
  end
end
