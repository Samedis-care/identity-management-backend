# libvips reads and writes formats through "loaders" and "savers", some of which
# it flags as "unfuzzed"/untrusted: they are backed by third-party libraries that
# are only safe for trusted content. Feeding attacker-supplied files to them can
# disclose arbitrary files readable by this process, potentially RCE.
# See CVE-2026-66066 / GHSA-xr9x-r78c-5hrm — reported against Active Storage,
# which we do not load (see config/application.rb); the underlying problem is
# libvips, which we do use.
#
# image_processing 2.0 already calls Vips.block_untrusted(true) when
# image_processing/vips is required, but not every path into libvips goes through
# that gem: DeviseMailer#logo hands the app's configured logo_b64 straight to
# Vips::Image.new_from_file. Blocking here makes it explicit and independent of
# load order.
#
# Requiring image_processing/vips first is deliberate: that require calls
# block_untrusted itself, which re-blocks the SVG loaders re-enabled below. The
# require is idempotent, so the uploaders' own requires are no-ops and cannot
# undo this.
require 'image_processing/vips'

unless Vips.at_least_libvips?(8, 13)
  raise "libvips #{Vips.version_string} cannot block untrusted operations — 8.13 or newer is required"
end

Vips.block_untrusted(true)

# The SVG loader (librsvg) is one of the untrusted ones, but SVG is an accepted
# upload format for user and actor images. Re-enable just those three loaders;
# every other untrusted loader/saver (BMP, ICO, PSD, JPEG XL, JPEG 2000, Netpbm,
# FITS, Matlab, OpenSlide, anything delegated to ImageMagick) stays blocked.
#
# ImageUploader and ActorImageUploader validate against a png/jpeg/svg allowlist
# with content sniffing (marcel) before any of this runs, so only content that
# actually looks like SVG reaches librsvg. To drop SVG support entirely, delete
# this block and remove image/svg+xml from both uploaders.
%w[
  VipsForeignLoadSvgFile
  VipsForeignLoadSvgBuffer
  VipsForeignLoadSvgSource
].each { |loader| Vips.block(loader, false) }
