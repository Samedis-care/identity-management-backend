require 'rails_helper'

# Guards config/initializers/vips.rb (CVE-2026-66066 / GHSA-xr9x-r78c-5hrm).
#
# The load order is the fragile part: image_processing/vips calls
# Vips.block_untrusted(true) whenever it is required, which re-blocks the SVG
# loaders the initializer re-enables. The initializer therefore requires
# image_processing/vips itself, before unblocking SVG. Touching the uploaders
# here re-triggers that require the way eager loading does in production.
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

  before { [ImageUploader, ActorImageUploader].each(&:name) }

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

  it 'processes an SVG through the uploader pipeline' do
    source = tempfile(svg(40), '.svg').path
    processed = ImageProcessing::Vips.source(source).resize_to_limit(20, 20).convert('png').call
    expect(File.size(processed.path)).to be > 0
  end
end
