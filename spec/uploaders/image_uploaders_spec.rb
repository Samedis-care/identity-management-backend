require 'rails_helper'
require 'shrine/storage/memory'

# CVE-2026-66066 / GHSA-xr9x-r78c-5hrm: both image uploaders accepted any content
# type — they had no validations at all — so arbitrary uploaded bytes reached
# libvips with the loader chosen by content sniffing. Uploads are now restricted
# to ImageUploader::MIME_TYPES.
describe 'image upload MIME allowlist', type: :model do
  # Shrine dups @storages into every subclass at class-definition time
  # (shrine.rb#inherited), and both uploaders are defined after
  # config/initializers/shrine.rb ran — so reassigning Shrine.storages would not
  # reach them and the examples would upload to the configured FileSystem cache,
  # leaving files in public/uploads/cache. Override on the classes under test.
  around do |example|
    originals = { ImageUploader => ImageUploader.storages,
                  ActorImageUploader => ActorImageUploader.storages }
    originals.each_key do |klass|
      klass.storages = { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }
    end
    example.run
    originals.each { |klass, storages| klass.storages = storages }
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

  # HEIF/AVIF/WebP savers are optional in a libvips build, so a machine that
  # cannot write the fixture skips instead of failing. The loaders are what
  # matters in production and they are not part of the untrusted set.
  def image_buffer(extension)
    Vips::Image.black(4, 4).write_to_buffer(extension)
  rescue Vips::Error
    skip "libvips #{Vips.version_string} cannot write #{extension} here"
  end

  def svg
    '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4"/></svg>'
  end

  def pdf
    "%PDF-1.4\n1 0 obj\n<< >>\nendobj\ntrailer\n<< >>\n%%EOF\n"
  end

  # Designer export: XML prolog, generator comment, DOCTYPE and editor namespaces
  # push <svg> to roughly offset 250.
  def designer_svg
    <<~SVG
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <!-- Generator: Adobe Illustrator 28.0.0, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
      <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
      <svg version="1.1" id="Ebene_1" xmlns="http://www.w3.org/2000/svg"
           xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" viewBox="0 0 200 100"
           style="enable-background:new 0 0 200 100;" xml:space="preserve">
        <style type="text/css">.st0{fill:#004E7D;}</style>
        <rect class="st0" width="200" height="100"/>
      </svg>
    SVG
  end

  describe ImageUploader do
    let(:record)   { User.new(email: 'vips-spec@example.com') }
    let(:attacher) { record.image_attacher }

    it 'accepts PNG' do
      expect(assign(attacher, png).errors).to be_empty
    end

    it 'accepts JPEG' do
      expect(assign(attacher, image_buffer('.jpg'), filename: 'upload.jpg').errors).to be_empty
    end

    it 'accepts SVG' do
      expect(assign(attacher, svg, filename: 'upload.svg').errors).to be_empty
    end

    # Avatars come off phones, so the camera formats have to stay uploadable.
    it 'accepts HEIC' do
      expect(assign(attacher, image_buffer('.heic'), filename: 'upload.heic').errors).to be_empty
    end

    it 'accepts WebP' do
      expect(assign(attacher, image_buffer('.webp'), filename: 'upload.webp').errors).to be_empty
    end

    it 'rejects a PDF even when it is named .png' do
      expect(assign(attacher, pdf).errors).not_to be_empty
    end

    it 'rejects a Netpbm image, whose libvips loader is untrusted' do
      expect(assign(attacher, "P3\n1 1\n255\n0 0 0\n", filename: 'upload.ppm').errors).not_to be_empty
    end

    # marcel sniffs content, and Shrine calls it without a filename, so a
    # designer export — XML prolog, generator comment, DOCTYPE and editor
    # namespaces before <svg> appears ~250 bytes in — has to be recognised just
    # as well as a bare <svg ...> fixture. App logos arrive in exactly this shape.
    it 'accepts an SVG whose <svg> element starts after a prolog and DOCTYPE' do
      assign(attacher, designer_svg, filename: 'logo.svg')
      expect(attacher.file.mime_type).to eq('image/svg+xml')
      expect(attacher.errors).to be_empty
    end

    # image_b64= is the API entry point (User#image_b64=, Actor#image_b64=), and
    # Base64StringIO keeps the content type the client declared in the data URI.
    # The allowlist has to hold against that claim rather than trust it.
    it 'rejects an image_b64 data URI whose declared image/png contradicts its content' do
      record.image_b64 = "data:image/png;base64,#{Base64.strict_encode64("P3\n1 1\n255\n0 0 0\n")}"
      expect(record.image_attacher.errors).not_to be_empty
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

    it 'accepts HEIC' do
      expect(assign(attacher, image_buffer('.heic'), filename: 'upload.heic').errors).to be_empty
    end

    it 'rejects a PDF even when it is named .png' do
      expect(assign(attacher, pdf).errors).not_to be_empty
    end

    it 'shares ImageUploader::MIME_TYPES rather than keeping its own copy' do
      expect(assign(attacher, "P3\n1 1\n255\n0 0 0\n", filename: 'upload.ppm').errors).not_to be_empty
    end
  end
end
