require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#3537: Actor#handle_soft_delete assigned
# local variables instead of the attribute, so deleted_at was never persisted.
RSpec.describe Actor, '#handle_soft_delete' do
  let(:sfx) { SecureRandom.hex(4) }

  let!(:tenant) { Actors::Tenant.create!(name: "soft-delete-tenant-#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
  let!(:group) { Actors::Group.create!(name: "group-#{sfx}", parent: tenant_profiles, system: true) }

  after do
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    tenant.delete
  end

  def soft_delete!(actor)
    actor.system_override = true # system groups refuse deletion otherwise
    actor.update!(deleted: true)
  end

  it 'persists deleted_at when an actor is soft deleted' do
    soft_delete!(group)

    expect(Actor.find(group.id).deleted_at).to be_within(5.seconds).of(Time.now)
  end

  it 'keeps the original deleted_at when an already deleted actor is saved again' do
    soft_delete!(group)
    first = Actor.find(group.id).deleted_at
    expect(first).not_to be_nil

    sleep 0.01
    again = Actor.find(group.id)
    again.system_override = true
    again.save!

    expect(Actor.find(group.id).deleted_at).to eq(first)
  end

  it 'clears deleted_at when an actor is undeleted' do
    soft_delete!(group)
    expect(Actor.find(group.id).deleted_at).not_to be_nil

    group.reload
    group.system_override = true
    group.update!(deleted: false)

    expect(Actor.find(group.id).deleted_at).to be_nil
  end
end
