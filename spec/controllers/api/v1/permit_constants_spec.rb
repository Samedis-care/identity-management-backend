require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2814.
#
# OpenapiSpecGenerator#attributes derives a request body ONLY from the controller's
# PERMIT_CREATE / PERMIT_UPDATE constants. A controller that permits its attributes
# by overriding params_create / params_update directly (and leaves the constant at the
# JsonApiController default of []) gets published as "This endpoint does not support
# sending any attributes" -- 14 endpoints were documented that way while accepting
# real attributes.
RSpec.describe Api::V1::JsonApiController do
  # Loading config/routes.rb (triggered by eager loading the controllers) needs a Devise
  # secret key, which comes from ENV['DEVISE_SECRET_KEY'] and is not always defined in a
  # plain test run.
  before(:all) do
    @devise_secret_key = Devise.secret_key
    Devise.secret_key ||= 'x' * 64
    Rails.application.eager_load!
  end

  after(:all) { Devise.secret_key = @devise_secret_key }

  # [action, permit constant, params method]
  {
    create: %i[PERMIT_CREATE params_create],
    update: %i[PERMIT_UPDATE params_update]
  }.each do |action, (constant, params_method)|
    it "declares #{constant} for every controller that overrides #{params_method}" do
      offenders = described_class.descendants.select do |controller|
        next false if controller.name.blank?
        next false unless controller.private_method_defined?(params_method)
        next false if controller.instance_method(params_method).owner.eql?(described_class)
        next false unless controller.public_method_defined?(action)

        controller.const_get(constant).empty?
      end

      expect(offenders.map(&:name)).to be_empty
    end
  end

  describe 'the permit lists now published for the controllers fixed in #2814' do
    {
      Api::V1::EmailBlacklistController => { create: %i[active domain], update: %i[active domain] },
      Api::V1::User::TenantsController => {
        create: %i[full_name image image_b64 short_name],
        update: %i[full_name image image_b64 short_name]
      },
      Api::V1::User::InvitationsController => {
        create: %i[auto_accept invitable_id invitable_type tenant_id user_id]
      },
      Api::V1::AccessControl::Tenant::UsersController => { update: %i[access_group_ids] },
      Api::V1::AccessControl::Apps::Tenant::UsersController => { update: %i[access_group_ids] },
      Api::V1::Apps::ContentsController => {
        create: %i[acceptance_required active content_translations name],
        update: %i[acceptance_required active content_translations name]
      }
    }.each do |controller, expected|
      expected.each do |action, attributes|
        it "#{controller.name} #{action} permits #{attributes.join(', ')}" do
          expect(controller.public_send(:"permitted_attributes_for_#{action}").sort).to eq(attributes)
        end
      end
    end
  end
end
