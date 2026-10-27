require 'rails_helper'

# Regression cover for Samedis-care/samedis-care-issues#3536: Actor#before_save cascaded
# `deleted` to descendants on every save, so saving a tenant undeleted every OU/group
# that had been soft-deleted below it.
RSpec.describe Actor, 'soft-delete cascade' do
  let(:sfx) { SecureRandom.hex(4) }

  let!(:tenant) { Actors::Tenant.create!(name: "soft-delete-tenant-#{sfx}") }
  let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
  let!(:ou) { Actors::Ou.create!(name: "ou#{sfx}", parent: organization) }
  let!(:group) { Actors::Group.create!(name: "group#{sfx}", parent: ou, system: true) }
  let!(:control_group) { Actors::Group.create!(name: "control#{sfx}", parent: organization, system: true) }

  after do
    Actor.where(:parent_ids.in => [tenant.id]).delete_all
    tenant.delete
  end

  def soft_delete!(actor)
    actor.reload
    actor.deleted = true
    actor.save(validate: false)
  end

  it 'cascades a delete to the descendants' do
    soft_delete!(ou)

    expect(group.reload.deleted).to be(true)
    expect(control_group.reload.deleted).to be(false)
  end

  it 'does not undelete soft-deleted descendants when a live ancestor is saved' do
    soft_delete!(ou)

    tenant.reload
    expect(tenant.changed?).to be(false)
    tenant.save!
    organization.reload.save!

    expect(ou.reload.deleted).to be(true)
    expect(group.reload.deleted).to be(true)
    expect(control_group.reload.deleted).to be(false)
  end

  it 'does not undelete when the live ancestor really changes' do
    soft_delete!(ou)

    tenant.reload
    tenant.update!(title: "renamed-#{sfx}")

    expect(ou.reload.deleted).to be(true)
    expect(group.reload.deleted).to be(true)
  end

  it 'still cascades an explicit undelete' do
    soft_delete!(ou)
    ou.reload
    ou.deleted = false
    ou.save(validate: false)

    expect(group.reload.deleted).to be(false)
  end
end
