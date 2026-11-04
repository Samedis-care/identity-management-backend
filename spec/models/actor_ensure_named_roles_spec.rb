require 'rails_helper'

# Samedis-care/samedis-care-issues#3533: a group in the actor defaults named a
# misspelled role, ensure_named_roles dropped the unknown name, and the group
# granted nothing without anyone noticing.
RSpec.describe Actor, '#ensure_named_roles' do
  let(:sfx) { SecureRandom.hex(4) }
  let!(:app) { Actors::App.create!(name: "named-roles-app-#{sfx}") }
  let!(:role) { Role.create!(name: "named-roles-role-#{sfx}", app: app.name) }
  let!(:organization) { Actors::Organization.create!(name: "named-roles-org-#{sfx}", parent: app) }
  let(:typo) { "named-rles-role-#{sfx}" }

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
  def ensure_defaults_with(*role_names)
    Actors::Organization.find(organization.id).ensure_defaults!(with_defaults: defaults(*role_names))
  end

  def group
    Actors::Group.find_by(parent_ids: organization.id, name: "grp#{sfx}")
  end

  before { allow(Sentry).to receive(:capture_message) }

  after do
    described_class.where(:parent_ids.in => [app.id]).delete_all
    app.delete
    role.delete
  end

  it 'reports a role name that matches no role and keeps the known ones' do
    ensure_defaults_with(role.name, typo)

    expect(group.role_ids).to eq([role.id])
    expect(Sentry).to have_received(:capture_message).with(
      'Actor#ensure_named_roles: actor defaults name a role that does not exist',
      hash_including(level: :warning, extra: hash_including(role_names: [typo], actor_id: group.id.to_s))
    )
  end

  it 'reports nothing when every role name exists' do
    ensure_defaults_with(role.name)

    expect(group.role_ids).to eq([role.id])
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
