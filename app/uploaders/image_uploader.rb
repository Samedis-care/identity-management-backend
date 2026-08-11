#require "image_processing/mini_magick"
require "image_processing/vips" # faster

class ImageUploader < Shrine

  plugin :model, cache: false
  plugin :signature
  plugin :add_metadata
  plugin :determine_mime_type, analyzer: :marcel
  plugin :derivatives, versions_compatibility: true
  plugin :validation_helpers
  # With `model, cache: false` an assignment uploads to permanent :store before
  # the validation below runs, so a rejected file would sit in the bucket
  # unreferenced forever — the record never saves. remove_invalid destroys it.
  plugin :remove_invalid

  # Formats libvips can read with a fuzzed (trusted) loader, plus SVG, which
  # config/initializers/vips.rb re-enables deliberately. Without this list,
  # arbitrary uploaded bytes reach libvips and the loader is picked by content
  # sniffing — see that initializer and CVE-2026-66066. None of these loaders is
  # part of libvips' untrusted set, so allowing them costs nothing against the
  # CVE; what the list buys is rejecting content that is not an image at all,
  # with a clean validation error. HEIC/HEIF/AVIF and WebP matter because avatars
  # come off phones, GIF and TIFF because they were uploadable before this list
  # existed and turning a working upload into an error is the worse failure.
  #
  # The MIME type comes from marcel content analysis (determine_mime_type
  # plugin), not from the client-supplied header — which matters for
  # User#image_b64= and Actor#image_b64=, where Base64StringIO carries the
  # content type the client declared in the data URI.
  MIME_TYPES = %w[
    image/png
    image/jpeg
    image/svg+xml
    image/heic
    image/heif
    image/avif
    image/webp
    image/gif
    image/tiff
  ].freeze

  Attacher.validate do
    validate_mime_type_inclusion ImageUploader::MIME_TYPES
  end

  add_metadata do |io, context|
    filename = context[:record].id
    filename = context[:record].email if context[:record].is_a?(User)
    filename = context[:record].name if context[:record].is_a?(Actor)
    {
      filename: filename
    }
  end

  def generate_location(io, **context)
    "uploads/#{context[:record].class.to_s.downcase}/#{context[:record].id.to_s}/#{super}"
  end

  Attacher.derivatives download: false do |io|
    versions = {}

    io.download do |original|
      begin
        @@semaphore.acquire
        pipeline = ImageProcessing::Vips.source(original)

        versions[:large] = pipeline.convert('png').resize_to_fill!(800, 800)
        versions[:medium] = pipeline.convert('png').resize_to_fill!(400, 400)
        versions[:small] = pipeline.convert('png').resize_to_fill!(200, 200)
      ensure
        @@semaphore.release
      end
    end

    versions # return the hash of processed files
  end

  private

  # Semaphore to limit concurrent resize activity.
  # Limit to n thread(s) per process (process = cpu core in production)
  # This is needed to prevent out of memory errors
  @@semaphore = Concurrent::Semaphore.new(2)

end