class Base64StringIO < StringIO

  def self.to_base64(filename)
    File.open(filename, 'rb') do |f|
      'data:image/png;base64,' + Base64.strict_encode64(f.read)
    end
  end

  def self.from_base64(encoded_file, filename=nil)
    # detect if the file is an url
    _url = URI.parse(encoded_file[0..1024].split(',')[0]) rescue nil
    return nil if (_url.try(:host).present? || _url.try(:opaque).blank?)
    handle_base64(encoded_file, filename)
  end

  def self.handle_base64(encoded_file, filename=nil)
    head, data = encoded_file.split(';base64,', 2)
    head.match(%r{^data:(.*?)(?:;(.*?))?$})
    content_type = $1
    filename ||= begin
      parameter = $2.to_s.split(';').collect { |m|
        m.split('=',2)
      }.map{ |k,v|
        [k,(_parser.decode(v) rescue nil)]
      }.to_h.with_indifferent_access
      parameter[:name]
    end
    filename ||= begin
      extension = content_type.split('/').last.downcase rescue nil
      "file-#{Time.now.to_i}.#{extension}"
    end
    file = new(Base64.decode64(data))
    file.content_type = content_type
    file.original_filename = filename
    file
  end

  def original_filename
    @original_filename || 'filename'
  end
  def original_filename=(filename)
    @original_filename = filename
  end
  def content_type=(content_type)
    @content_type = content_type
  end
  def content_type
    @content_type
  end

end
