require 'rails_helper'
require 'shrine/storage/memory'

# CVE-2026-66066 / GHSA-xr9x-r78c-5hrm: both image uploaders accepted any content
# type, so arbitrary uploaded bytes reached libvips with the loader chosen by
# content sniffing. Uploads are now restricted to the formats whose derivatives
# we actually render.
describe 'image upload MIME allowlist', type: :model do
  around do |example|
    original_storages = Shrine.storages
    Shrine.storages = { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }
    example.run
    Shrine.storages = original_storages
  end

  # Uploads bytes under a *harmless* extension on purpose: the allowlist has to
  # hold on sniffed content (marcel), not on the name the client supplied.
  def assign(attacher, bytes, filename: 'upload.png')
    file = Tempfile.new([File.basename(filename, '.*'), File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    attacher.assign(file)
    attacher
  end

  def png
    Vips::Image.black(4, 4).write_to_buffer('.png')
  end

  def svg
    '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4"/></svg>'
  end

  def pdf
    "%PDF-1.4\n1 0 obj\n<< >>\nendobj\ntrailer\n<< >>\n%%EOF\n"
  end

  describe ImageUploader do
    let(:record)   { User.new(email: 'vips-spec@example.com') }
    let(:attacher) { record.image_attacher }

    it 'accepts PNG' do
      expect(assign(attacher, png).errors).to be_empty
    end

    it 'accepts JPEG' do
      expect(assign(attacher, Vips::Image.black(4, 4).write_to_buffer('.jpg'),
                    filename: 'upload.jpg').errors).to be_empty
    end

    it 'accepts SVG' do
      expect(assign(attacher, svg, filename: 'upload.svg').errors).to be_empty
    end

    it 'rejects a PDF even when it is named .png' do
      expect(assign(attacher, pdf).errors).not_to be_empty
    end

    it 'rejects a Netpbm image, whose libvips loader is untrusted' do
      expect(assign(attacher, "P3\n1 1\n255\n0 0 0\n", filename: 'upload.ppm').errors).not_to be_empty
    end
  end

  describe ActorImageUploader do
    let(:record)   { Actor.new(name: 'vips-spec') }
    let(:attacher) { record.image_attacher }

    it 'accepts PNG' do
      expect(assign(attacher, png).errors).to be_empty
    end

    it 'accepts SVG' do
      expect(assign(attacher, svg, filename: 'upload.svg').errors).to be_empty
    end

    it 'rejects a PDF even when it is named .png' do
      expect(assign(attacher, pdf).errors).not_to be_empty
    end
  end
end
