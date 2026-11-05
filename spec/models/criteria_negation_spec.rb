require 'rails_helper'

# Regression coverage for https://github.com/Samedis-care/samedis-care-issues/issues/3397
#
# Mongoid 9.1.1 deprecates Criteria#not without arguments (it flips a "negating"
# flag for whatever condition comes next); Mongoid 10 removes it. Every scope below
# used that form and now passes its condition to #not, or uses :field.ne.
#
# Where the rewrite keeps the selector byte for byte, the selector is pinned. Where
# the selector changes shape ($not/$in or $not/$lt becoming $nor), the old and new
# selectors are run against the same documents in a scratch collection, including the
# missing-field and nil cases that $nor and $not treat alike.
RSpec.describe Mongoid::Criteria, 'negation without the deprecated argument-less #not' do
  let(:now) { Time.now.utc }

  def matching_keys(selector, docs)
    collection = Mongoid.default_client["criteria_negation_spec_#{SecureRandom.hex(4)}"]
    collection.insert_many(docs)
    collection.find(selector).map { |doc| doc['k'] }.sort
  ensure
    collection&.drop
  end

  it 'never reaches the :not_sans_arguments deprecation' do
    user = User.new(email: "criteria-negation-#{SecureRandom.hex(4)}@test.local")
    activity_controller = Api::V1::User::AccountActivityController.new
    allow(activity_controller).to receive(:current_user).and_return(user)
    picker_controller = Api::V1::Picker::ActorsController.new
    allow(Mongoid).to receive(:deprecation_warning).and_call_original

    [
      Actor.available, Download.available, User.writable, User.deletable, User.login_allowed,
      picker_controller.send(:model_index), picker_controller.send(:model_show),
      activity_controller.send(:model_index)
    ].each(&:selector)

    expect(Mongoid).not_to have_received(:deprecation_warning).with(:not_sans_arguments, any_args)
  end

  it 'keeps the $ne selectors of ApplicationDocument.available, User.writable and User.deletable' do
    expect(Actor.available.selector).to eq('deleted' => { '$ne' => true })
    expect(User.writable.selector).to eq('write_protected' => { '$ne' => true })
    expect(User.deletable.selector).to eq('system' => { '$ne' => true })
  end

  describe 'User.login_allowed' do
    it 'excludes exactly the users whose invalid_at has passed, as the old $not/$lt did' do
      docs = [
        { k: 'missing' }, { k: 'nil', invalid_at: nil },
        { k: 'past', invalid_at: now - 3600 }, { k: 'future', invalid_at: now + 3600 }
      ]
      old_selector = { 'invalid_at' => { '$not' => { '$lt' => now } } }
      new_selector = User.all.not(:invalid_at.lt => now).selector

      expect(matching_keys(new_selector, docs)).to eq(matching_keys(old_selector, docs))
      expect(matching_keys(new_selector, docs)).to eq(%w[future missing nil])
    end
  end

  describe 'Api::V1::Picker::ActorsController' do
    it 'leaves out mappings and users, as the old $not/$in did' do
      docs = [
        { k: 'missing' }, { k: 'mapping', _type: 'Actors::Mapping' },
        { k: 'user', _type: 'Actors::User' }, { k: 'group', _type: 'Actors::Group' }
      ]
      old_selector = { '_type' => { '$not' => { '$in' => %w[Actors::Mapping Actors::User] } } }
      controller = Api::V1::Picker::ActorsController.new
      new_selector = controller.send(:model_show).selector.except('deleted')

      expect(matching_keys(new_selector, docs)).to eq(matching_keys(old_selector, docs))
      expect(matching_keys(new_selector, docs)).to eq(%w[group missing])
      expect(controller.send(:model_index).options[:sort]).to eq('short_name' => 1)
    end
  end

  describe 'Download.available' do
    # The old `all.not.expired` negated the raw hash `expires_at: {'$lt' => ...}` into
    # `{'$ne' => {'$lt' => ...}}`, an equality test against a subdocument that matched
    # every download. Download.available has no caller; it now means what it says.
    it 'leaves out expired downloads' do
      docs = [{ k: 'expired', expires_at: now - 3600 }, { k: 'valid', expires_at: now + 3600 }]

      expect(matching_keys(Download.available.selector, docs)).to eq(%w[valid])
    end

    # Criteria#method_missing runs class-method scopes inside the caller's scope, so a
    # negated scope Criteria would also negate the caller's own conditions.
    it 'keeps the conditions of the criteria it is chained onto' do
      docs = [
        { k: 'mine_valid', name: 'mine', expires_at: now + 3600 },
        { k: 'mine_expired', name: 'mine', expires_at: now - 3600 },
        { k: 'other_valid', name: 'other', expires_at: now + 3600 }
      ]

      expect(matching_keys(Download.where(name: 'mine').available.selector, docs)).to eq(%w[mine_valid])
    end
  end
end
