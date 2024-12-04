# encoding: utf-8
class String
  # Writes the string into the given filename @param filename {String} Filename with optional path (otherwise saves to /ror)
  def to_file(filename)
    File.open(filename, 'w') do |file|
      file.puts self
    end
    File.exist?(filename)
  end

  def to_safe_filename
    self.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").strip.tr("\u{202E}%$|:;/\t\r\n\\", "-")
  end

  def to_boolean
    ActiveModel::Type::Boolean.new.cast(self.downcase)
  end

  #unicode aware function
  def to_slug
    # become case-insensitive
    value = self.mb_chars.downcase

    # replace dots with spaces
    value.gsub!(/\.+/, ' ')

    # replace any spaces, separators, or connector punctuation with spaces
    value.gsub!(/[\p{Separator}\p{Dash_Punctuation}]+/, ' ')

    # replace connectors with underscore
    value.gsub!(/[\p{Connector_Punctuation}]+/, '_')

    # remove any url-unsafe character with a space
    value.gsub!(/[:?#\/\\+@=]+/, ' ')

    # ampersand == and
    value.gsub!(/(?: ?&+ ?)+/, ' and ')

    # remove any whitespace before and after the string
    value.strip!

    # replace spaces with dashes
    value.gsub!(/\s+/, '-')

    # replace unsupported characters
    value.gsub!(/[\p{Other}]/, '')
    value.gsub!(/[\p{Open_Punctuation}\p{Close_Punctuation}\p{Initial_Punctuation}\p{Final_Punctuation}\p{Other_Punctuation}]/, '')

    # done, here's the slug!
    value.to_s
  end

  # Remove non-latin characters form strings for safe full-text indexing
  def strip_diacritics
    # latin1 subset only
    self.gsub(/ä/, "ae").
         gsub(/Ä/, "Ae").
         gsub(/ö/, "oe").
         gsub(/Ö/, "Oe").
         gsub(/ü/, "ue").
         gsub(/Ü/, "Ue").
         gsub(/Æ/, "AE").
         gsub(/Ð/, "Eth").
         gsub(/Þ/, "THORN").
         gsub(/ß/, "ss").
         gsub(/æ/, "ae").
         gsub(/ð/, "eth").
         gsub(/þ/, "thorn").
         tr("ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöøùúûüýÿ",
            "AAAAAACEEEEIIIINOOOOOOUUUUYaaaaaaceeeeiiiinoooooouuuuyy")
  end

  def to_clipboard
    begin
      Clipboard.copy self
    rescue => e
      raise
    end
  end

end
