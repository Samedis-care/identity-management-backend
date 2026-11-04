require 'rails_helper'

# Samedis-care/samedis-care-issues#3444: clients must be able to tell predefined (system) access
# profiles apart from custom ones, since only the latter can be deleted.
RSpec.describe GroupActorSerializer do
  def attributes_for(group)
    described_class.new(group).serializable_hash.dig(:data, :attributes)
  end

  it 'serves system for a predefined group' do
    expect(attributes_for(Actors::Group.new(system: true))).to include(system: true)
  end

  it 'serves system false for a custom group' do
    expect(attributes_for(Actors::Group.new(system: false))).to include(system: false)
  end
end
