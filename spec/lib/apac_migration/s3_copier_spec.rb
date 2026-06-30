require 'rails_helper'
require Rails.root.join('lib/apac_migration/s3_copier')

RSpec.describe ApacMigration::S3Copier do
  describe '.keys_from' do
    it 'returns [] for blank input' do
      expect(described_class.keys_from(nil)).to eq([])
      expect(described_class.keys_from({})).to eq([])
    end

    it 'extracts keys from the flat versions form (versions_compatibility)' do
      image_data = {
        'large'  => { 'id' => 'uploads/user/1/a.png', 'storage' => 'store' },
        'medium' => { 'id' => 'uploads/user/1/b.png', 'storage' => 'store' },
        'small'  => { 'id' => 'uploads/user/1/c.png', 'storage' => 'store' }
      }
      expect(described_class.keys_from(image_data)).to contain_exactly(
        'uploads/user/1/a.png', 'uploads/user/1/b.png', 'uploads/user/1/c.png'
      )
    end

    it 'extracts the original plus nested derivatives' do
      image_data = {
        'id' => 'uploads/actor/2/orig.png', 'storage' => 'store',
        'derivatives' => {
          'large' => { 'id' => 'uploads/actor/2/l.png', 'storage' => 'store' }
        }
      }
      expect(described_class.keys_from(image_data)).to contain_exactly(
        'uploads/actor/2/orig.png', 'uploads/actor/2/l.png'
      )
    end

    it 'parses a JSON string and de-duplicates' do
      json = { 'large' => { 'id' => 'k.png', 'storage' => 'store' } }.to_json
      expect(described_class.keys_from(json)).to eq(['k.png'])
    end

    it 'ignores hashes without a storage sibling (not a stored file)' do
      image_data = { 'metadata' => { 'id' => 'not-a-key', 'filename' => 'x' } }
      expect(described_class.keys_from(image_data)).to eq([])
    end
  end
end
