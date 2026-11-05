require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#3444: soft-deleting a record whose save
# was refused (e.g. a predefined/system access profile) answered 200 success and deleted nothing.
# Only the hard-destroy branch collected undeletables; the soft-delete branch ignored the result
# of #save. Refused records must now be reported as a 409 like hard-destroy refusals.
RSpec.describe Api::V1::JsonApiController, '#destroy' do
  subject(:controller_instance) { Api::V1::AccessControl::Tenant::ProfilesController.new }

  let(:sfx) { SecureRandom.hex(4) }

  let!(:tenant) { Actors::Tenant.create!(name: "destroy-tenant-#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:system_group) { Actors::Group.create!(name: "system-#{sfx}", parent: tenant_profiles, system: true) }
  # created as system so Group#safe_role_ids skips the tenant's app defaults this spec has none of
  let!(:custom_group) do
    Actors::Group.create!(name: "custom-#{sfx}", parent: tenant_profiles, system: true).tap { it.set(system: false) }
  end

  let(:rendered) { {} }

  before do
    allow(controller_instance).to receive(:render_jsonapi_msg) do |msg, status|
      rendered[:msg] = msg
      rendered[:status] = status
    end
  end

  after do
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    tenant.delete
  end

  def destroy!(*records)
    allow(controller_instance).to receive(:records_destroy).and_return(records)
    controller_instance.destroy
  end

  it 'refuses a system group with 409 and leaves it undeleted' do
    destroy!(system_group)

    expect(rendered[:status]).to eq(409)
    expect(rendered[:msg]).to include(success: false, error: :conflict)
    expect(rendered[:msg][:error_details]).to eq(system_group.id => [I18n.t('errors.attributes.system.protected')])
    expect(Actor.find(system_group.id).deleted).to be(false)
  end

  it 'soft-deletes a custom group with 200' do
    destroy!(custom_group)

    expect(rendered[:status]).to eq(200)
    expect(rendered[:msg]).to include(success: true, error: nil)
    expect(Actor.find(custom_group.id).deleted).to be(true)
  end

  it 'deletes the deletable records of a mixed selection and reports the refused ones' do
    destroy!(custom_group, system_group)

    expect(rendered[:status]).to eq(409)
    expect(rendered[:msg][:message]).to eq(I18n.t('errors.undeletable', count: 1, total: 2))
    expect(rendered[:msg][:error_details].keys).to eq([system_group.id])
    expect(Actor.find(custom_group.id).deleted).to be(true)
    expect(Actor.find(system_group.id).deleted).to be(false)
  end

  it 'refuses a write-protected group with 409' do
    custom_group.set(write_protected: true)

    destroy!(Actor.find(custom_group.id))

    expect(rendered[:status]).to eq(409)
    expect(Actor.find(custom_group.id).deleted).to be(false)
  end

  # Actor#before_save hard-deletes a mapping flagged deleted and then aborts the save, so a false
  # #save is not a refusal here: the mapping is gone.
  context 'with a mapping' do
    let(:email) { "destroy-#{sfx}@json-api-destroy-spec.test" }
    let!(:user) do
      User.new(
        email: email,
        email_confirmation: email,
        first_name: 'Destroy',
        last_name: 'Spec',
        password: 'Sup3rSecret!123',
        password_confirmation: 'Sup3rSecret!123'
      ).tap do |u|
        u.skip_confirmation!
        u.save!
      end
    end

    after do
      Actors::Mapping.where(map_actor: user.actor).delete_all
      user.actor&.delete
      user.delete
    end

    it 'treats a mapping removed by its before_save as deleted' do
      mapping = custom_group.map_into!(user.actor)

      destroy!(mapping)

      expect(rendered[:status]).to eq(200)
      expect(Actors::Mapping.where(id: mapping.id)).not_to exist
    end
  end
end
