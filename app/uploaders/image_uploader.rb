#require "image_processing/mini_magick"
require "image_processing/vips" # faster

class ImageUploader < Shrine

  plugin :model, cache: false
  plugin :signature
  plugin :add_metadata
  plugin :determine_mime_type, analyzer: :marcel
  plugin :derivatives, versions_compatibility: true

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