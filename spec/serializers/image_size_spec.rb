require 'rails_helper'
require 'shrine/storage/memory'

# Samedis-care/samedis-care-issues#3528: the serializers of every endpoint that
# accepts an image upload expose the stored image's size in bytes as image_size,
# so a frontend can validate sizes against what is already on the server.
#
# Records are built unsaved with Shrine data hashes; nothing reaches the database.
describe 'image_size', type: :model do
  def stored(size)
    { 'id' => 'image-size-spec.png', 'storage' => 'store',
      'metadata' => { 'filename' => 'image-size-spec.png', 'size' => size, 'mime_type' => 'image/png' } }
  end

  def serialize(serializer, record)
    serializer.new(record, fields: { serializer.record_type => [:image_size] })
              .serializable_hash[:data][:attributes]
  end

  # [serializer, builder taking the Shrine data hash (nil = no image)]
  cases = [
    [UserSerializer, ->(data) { User.new(image_data: data) }],
    [AppUserSerializer, ->(data) { User.new(image_data: data) }],
    [TenantSerializer, ->(data) { Actors::Tenant.new(image_data: data) }],
    [ActorSerializer, ->(data) { Actors::Tenant.new(image_data: data) }]
  ]

  cases.each do |serializer, build|
    describe serializer do
      it 'is the size of the stored image' do
        expect(serialize(serializer, build.call(stored(54_321)))[:image_size]).to eq(54_321)
      end

      it 'is nil without an image' do
        expect(serialize(serializer, build.call(nil))[:image_size]).to be_nil
      end

      # images from before the derivatives plugin are stored as a versions hash
      it 'reads the original from image data in the legacy versions format' do
        record = build.call('original' => stored(54_321), 'large' => stored(4_321))

        expect(serialize(serializer, record)[:image_size]).to eq(54_321)
      end

      it 'is documented as a read-only, nullable integer' do
        property = serializer::Schema.new.openapi_component_produces_schema[:properties][:image_size]

        expect(property).to include('type' => 'integer', 'nullable' => true, 'readOnly' => true)
      end
    end
  end

  # Like the image URLs next to it: image data that cannot be loaded leaves the
  # attribute empty instead of failing the whole response.
  [UserSerializer, TenantSerializer, ActorSerializer].each do |serializer|
    it "is nil in #{serializer} for image data that cannot be loaded" do
      record = Actors::Tenant.new(image_data: stored(54_321).merge('storage' => 'unregistered'))
      record = User.new(image_data: record.image_data) if serializer == UserSerializer

      expect(serialize(serializer, record)[:image_size]).to be_nil
    end
  end

  # AppUserSerializer#tenants serializes the snapshot this builds
  it 'is in the tenant list of a user' do
    user = User.new
    allow(user).to receive(:candos).and_return({})
    tenants = [Actors::Tenant.new(image_data: stored(54_321)), Actors::Tenant.new]
    allow(Actors::Tenant).to receive(:criteria).and_return(tenants)

    expect(Actors::Tenant.tenant_collection(user).pluck(:image_size)).to eq([54_321, nil])
  end

  # The frontends upload a base64 data URI as image_b64, which Base64StringIO
  # wraps in a StringIO whose size Shrine records.
  describe 'an image uploaded as image_b64' do
    around do |example|
      original = ImageUploader.storages
      ImageUploader.storages = { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }
      example.run
      ImageUploader.storages = original
    end

    it 'reports the bytes of the upload' do
      png  = Vips::Image.black(4, 4).write_to_buffer('.png')
      user = User.new
      user.image_b64 = "data:image/png;base64,#{Base64.strict_encode64(png)}"

      expect(serialize(AppUserSerializer, user)[:image_size]).to eq(png.bytesize)
    end
  end
end
