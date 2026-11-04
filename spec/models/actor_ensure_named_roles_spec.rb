require 'rails_helper'

# Samedis-care/samedis-care-issues#3533: a group in the actor defaults named a
# misspelled role, ensure_named_roles dropped the unknown name, and the group
# granted nothing without anyone noticing.
RSpec.describe Actor, '#ensure_named_roles' do
  before { allow(Sentry).to receive(:capture_message) }

  let(:sfx) { SecureRandom.hex(4) }
  let!(:app) do
    Actors::App.create!(name: "named-roles-app-#{sfx}").tap(&:ensure_defaults!) # creates the tenants container
  end
  let!(:role) { Role.create!(name: "named-roles-role-#{sfx}", app: app.name) }
  let!(:tenant) { Actors::Tenant.create!(name: "named-roles-tenant-#{sfx}", parent: app.container_tenants) }
  let(:typo) { "named-rles-role-#{sfx}" }
  let(:message) { 'Actor#ensure_named_roles: actor defaults name a role that does not exist' }

  def defaults(*role_names)
    titles = { en: 'Named roles', de: 'Named roles' }
    {
      children: [{
        name: "ou#{sfx}", _type: 'Actors::Ou', title_translations: titles,
        children: [{
          name: "grp#{sfx}", _type: 'Actors::Group', system: false, title_translations: titles,
          roles: role_names
        }]
      }]
    }.deep_stringify_keys.with_indifferent_access
  end

  # a fresh instance per run: ensure_defaults! memoizes its result
  def ensure_defaults_with(*role_names, below: tenant.organization)
    Actors::Organization.find(below.id).ensure_defaults!(with_defaults: defaults(*role_names))
  end

  def group(below: tenant.organization)
    Actors::Group.find_by(parent_ids: below.id, name: "grp#{sfx}")
  end

  after do
    described_class.where(:parent_ids.in => [app.id]).delete_all
    app.delete
    role.delete
  end

  it 'reports a role name that matches no role and keeps the known ones' do
    ensure_defaults_with(role.name, typo)

    expect(group.role_ids).to eq([role.id])
    expect(Sentry).to have_received(:capture_message).once.with(
      message,
      hash_including(level: :warning, extra: hash_including(role_names: [typo], actor_id: group.id.to_s))
    )
  end

  it 'reports nothing when every role name exists' do
    ensure_defaults_with(role.name)

    expect(group.role_ids).to eq([role.id])
    expect(Sentry).not_to have_received(:capture_message)
  end

  it 'only logs an unknown role name outside a tenant' do
    app_organization = app.children.find_by(name: 'organization')
    allow(Rails.logger).to receive(:warn)

    ensure_defaults_with(typo, below: app_organization)

    expect(group(below: app_organization).role_ids).to eq([])
    expect(Rails.logger).to have_received(:warn).with(/no role named #{typo}/)
    expect(Sentry).not_to have_received(:capture_message)
  end

  it 'adds the role to the existing group once the defaults name it correctly' do
    ensure_defaults_with(typo)
    expect(group.role_ids).to eq([])
    group_id = group.id

    ensure_defaults_with(role.name)

    expect(group.id).to eq(group_id)
    expect(group.role_ids).to eq([role.id])
  end
end
