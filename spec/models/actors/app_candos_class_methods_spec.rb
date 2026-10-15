require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2661: Actors::App.dump_candos and
# Actors::App.seed_candos! called the instance-only helper dump_path_candos in class scope and
# raised NameError immediately (and seed_candos! would then have derived the app from the file
# name, which is always literally "candos"). They now follow the shape of their siblings
# (dump_roles, seed_roles!, ...): delegate to each available app's instance method.
RSpec.describe Actors::App, 'candos class methods' do
  let(:app_a) { instance_double(described_class, name: 'app-a', dump_candos: nil, seed_candos!: true) }
  let(:app_b) { instance_double(described_class, name: 'app-b', dump_candos: nil, seed_candos!: false) }

  before { allow(described_class).to receive(:available).and_return([app_a, app_b]) }

  describe '.dump_candos' do
    it 'does not raise NameError for the instance-only dump_path_candos' do
      expect { described_class.dump_candos }.not_to raise_error
    end

    it 'dumps the candos of every available app' do
      described_class.dump_candos

      expect(app_a).to have_received(:dump_candos)
      expect(app_b).to have_received(:dump_candos)
    end
  end

  describe '.seed_candos!' do
    it 'does not raise NameError for the instance-only dump_path_candos' do
      expect { described_class.seed_candos! }.to output.to_stdout
    end

    it 'seeds every available app through its own instance method, not through a file name' do
      expect { described_class.seed_candos! }.to output.to_stdout

      expect(app_a).to have_received(:seed_candos!)
      expect(app_b).to have_received(:seed_candos!)
    end

    it 'reports only the apps that actually had a candos.yml' do
      expect { described_class.seed_candos! }.to output("Seeded Candos for: app-a\n").to_stdout
    end
  end

  it 'does not need the instance-only path helper at class level' do
    expect(described_class).not_to respond_to(:dump_path_candos)
  end
end
