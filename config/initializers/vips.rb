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
# upload format for user and actor images. Re-enable it; every other untrusted
# loader/saver (BMP, ICO, PSD, JPEG XL, JPEG 2000, Netpbm, FITS, Matlab,
# OpenSlide, anything delegated to ImageMagick) stays blocked. Naming the parent
# class covers the file, buffer and source variants — vips_operation_block_set
# applies to the named class and everything below it.
#
# This is process-wide, not per-uploader, so every caller that reaches libvips
# needs its own content check, not just the uploaders — see
# DeviseMailer::LOGO_MIME_TYPES for the mail logo, which has no uploader in front
# of it.
#
# ImageUploader and ActorImageUploader both validate against
# ImageUploader::MIME_TYPES with content sniffing (marcel) before any of this
# runs, so only content that actually looks like SVG reaches librsvg — including
# on the User#image_b64= / Actor#image_b64= paths, where the content type the
# client declared in the data URI is not what gets validated.
#
# To drop SVG support entirely, delete this block and remove image/svg+xml from
# ImageUploader::MIME_TYPES.
# NOTE: Vips.block is a no-op for an unknown operation name, so a typo or a
# libvips built without librsvg fails silently — SVG simply stays blocked.
# spec/lib/vips_blocking_spec.rb is what catches that.
Vips.block('VipsForeignLoadSvg', false)
