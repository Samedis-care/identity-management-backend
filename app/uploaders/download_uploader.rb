class DownloadUploader < Shrine

  plugin :model, cache: false
  plugin :add_metadata

  add_metadata do |io, context|
    filename = context[:record].id
    filename = context[:record].name if context[:record].is_a?(Download)
    {
      filename: filename
    }
  end

  def generate_location(io, **context)
    "uploads/#{context[:record].class.to_s.downcase}/#{context[:record].id.to_s}/#{super}"
  end

end
