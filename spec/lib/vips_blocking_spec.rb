require 'rails_helper'

# Guards config/initializers/vips.rb (CVE-2026-66066 / GHSA-xr9x-r78c-5hrm).
#
# The load order inside that initializer is the fragile part: requiring
# image_processing/vips calls Vips.block_untrusted(true), which re-blocks the SVG
# loaders the initializer re-enables — so the require has to come first and the
# unblock last. What guards that here is the initializer itself: it runs at boot
# in the same order as in production, so reordering it (unblock before require)
# leaves SVG blocked and the SVG examples below fail.
describe 'libvips untrusted operation blocking', type: :model do
  def svg(size)
    %(<svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}">) +
      %(<rect width="#{size}" height="#{size}"/></svg>)
  end

  def tempfile(bytes, extension)
    file = Tempfile.new(['vips-blocking', extension])
    file.binmode
    file.write(bytes)
    file.rewind
    file
  end

  def loadable?(file)
    Vips::Image.new_from_file(file.path).avg
    true
  rescue Vips::Error
    false
  end

  it 'blocks untrusted loaders' do
    # Netpbm stands in for the whole untrusted set (BMP, ICO, PSD, JPEG XL,
    # JPEG 2000, FITS, Matlab, OpenSlide, ImageMagick delegates).
    expect(loadable?(tempfile("P3\n1 1\n255\n0 0 0\n", '.ppm'))).to be false
  end

  it 'still allows the SVG loader, which user and actor images accept' do
    expect(loadable?(tempfile(svg(4), '.svg'))).to be true
  end

  it 'still allows PNG' do
    expect(loadable?(tempfile(Vips::Image.black(4, 4).write_to_buffer('.png'), '.png'))).to be true
  end

  it 'still allows JPEG' do
    expect(loadable?(tempfile(Vips::Image.black(4, 4).write_to_buffer('.jpg'), '.jpg'))).to be true
  end

  it 'still allows the camera formats in ImageUploader::MIME_TYPES' do
    %w[.heic .webp].each do |extension|
      begin
        bytes = Vips::Image.black(4, 4).write_to_buffer(extension)
      rescue Vips::Error
        next # saver not compiled in here; the loader is what production needs
      end
      expect(loadable?(tempfile(bytes, extension))).to be(true), "#{extension} should still load"
    end
  end

  it 'processes an SVG through the uploader pipeline' do
    # Keep the Tempfile referenced: its finalizer unlinks the file on GC, and
    # libvips only opens it inside #call.
    source = tempfile(svg(40), '.svg')
    processed = ImageProcessing::Vips.source(source.path).resize_to_limit(20, 20).convert('png').call
    expect(File.size(processed.path)).to be > 0
  end
end
