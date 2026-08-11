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

  # The production path: `record.image =` goes through model_assign, which with
  # `model, cache: false` uploads to permanent :store before validating.
  def assign_via_model(record, bytes, filename: 'upload.png')
    file = Tempfile.new([File.basename(filename, '.*'), File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    record.image = file
    record
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

  # Encoder-independent: the HEIC/WebP examples below gate on the *saver* being
  # compiled in, so on a libvips without a HEIF encoder they skip and nothing would
  # notice a misspelled allowlist key. A constructed ftyp header needs no encoder.
  #
  # marcel 1.2.1 does have magic entries for all six HEIF brands (tables.rb
  # 2617-2621), but magic_match takes the *first* hit and video/quicktime's generic
  # [4, 'ftyp'] pattern (line 2530) sits ahead of the brand-specific ones — so only
  # heic/mif1/avif resolve to an image type, while heix/hevc/msf1 come back as
  # video/quicktime. Putting image/heic-sequence on the allowlist would therefore
  # buy nothing, and video/quicktime has no business on an image allowlist.
  describe 'the MIME types marcel emits for HEIF brands' do
    { 'ftypheic' => 'image/heic', 'ftypmif1' => 'image/heif', 'ftypavif' => 'image/avif' }
      .each do |brand, mime_type|
        it "detects #{brand} as #{mime_type}, which is on the allowlist" do
          io = StringIO.new("\x00\x00\x00\x18#{brand}\x00\x00\x00\x00".b)
          expect(Marcel::MimeType.for(io)).to eq(mime_type)
          expect(ImageUploader::MIME_TYPES).to include(mime_type)
        end
      end

    %w[ftypheix ftyphevc ftypmsf1].each do |brand|
      it "resolves #{brand} to video/quicktime, so the allowlist rejects it" do
        io = StringIO.new("\x00\x00\x00\x18#{brand}\x00\x00\x00\x00".b)
        detected = Marcel::MimeType.for(io)
        expect(detected).to eq('video/quicktime')
        expect(ImageUploader::MIME_TYPES).not_to include(detected)
      end
    end
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

    # The production path is `record.image =`, which with `model, cache: false`
    # uploads to permanent :store *before* validating. Without remove_invalid the
    # rejected bytes would stay in the bucket forever: the record never saves, so
    # nothing references or deletes them.
    it 'leaves nothing in permanent storage when the upload is rejected' do
      assign_via_model(record, pdf)
      expect(described_class.storages[:store].store).to be_empty
    end

    it 'keeps an accepted upload in permanent storage' do
      assign_via_model(record, png)
      expect(described_class.storages[:store].store).not_to be_empty
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
