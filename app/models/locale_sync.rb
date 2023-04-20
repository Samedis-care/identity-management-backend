class LocaleSync

  require "google_drive"

  TRANSLATED_LANGS = %i(en de ru it es fr)

  def self.get_ws(num)
    session = GoogleDrive::Session.from_config("google-sheet-session.json")
    # 0 SCB / 1 SCF / 2 IMB / 3 IMF / 4 Frontend Common
    ws = session.spreadsheet_by_key("1yfUpPsC5-D813hUe6Vce7GsBRdivzlkpw4ZwIqR8LQw").worksheets[num]
  end

  def self.get_remote_data
    ws = get_ws(2) # IMB sheet

    langs = (2..ws.num_cols).collect {|col| ws[1, col].to_s.downcase.to_sym }
    data = {}

    # first 2 rows are headers so start at 3
    (3..ws.num_rows).each do |row|
      data[ ws[row, 1] ] = {}
      (2..ws.num_cols).each do |col|
        lang = langs[col-2]
        data[ ws[row, 1] ][lang] = ws[row, col]
      end
    end

    data
  end

  def self.sync_data
    data_local = get_local_data # data from yml files
    data_remote = get_remote_data # data from google sheet

    data_remote.each do |k,v|
      data_local[k] ||= v
      l = v
      l.delete_if {|_,_v| _v.blank? }
      data_local[k].merge! l
    end
    data_local
  end


  # local yaml to data

  # turns nested hashes into flat dotted notation
  def self.flatten_hash(hash)
    hash.each_with_object({}) do |(k, v), h|
      if v.is_a? Hash
        flatten_hash(v).map do |h_k, h_v|
          h["#{k}.#{h_k}"] = h_v
        end
      else 
        h[k] = v
      end
     end
  end

  # turns dotted notation into nested
  def self.unflatten_hash_fragment(arr, value)
    if arr.empty?
      value
    else
      {}.tap do |hash|
        hash[arr.shift] = unflatten_hash_fragment(arr, value)
      end
    end
  end

  def self.unflatten_hash(data)
    unflattened_data = {}
    data.each do |k,v|
      fragment = unflatten_hash_fragment k.split('.'), v
      unflattened_data.deep_merge! fragment
    end
    unflattened_data
  end

  def self.local_dump(langs=TRANSLATED_LANGS)
    [langs].flatten.inject({}) do |hsh, lang|
      if I18n.locale_available?(lang)
        hsh[lang] = flatten_hash(YAML.load_file("config/locales/#{lang}.yml").stringify_keys[lang.to_s]) rescue {}
        puts "#{lang} #{hsh[lang].to_json}"
      else
        hsh[lang] = {}
      end
      hsh
    end
  end

  def self.get_local_data(langs: TRANSLATED_LANGS)
    data = {}
    translations = local_dump(langs)
    translations.keys.each do |lang|
      translations[lang].sort.each do |k,v|
        data[k] ||= {}
        data[k][lang] = v
      end
    end
    data
  end

  def self.as_xlsx(filename="#{Rails.application.class.parent_name}-locales.xlsx", langs: TRANSLATED_LANGS, data:sync_data)
    p = Axlsx::Package.new
    p.use_autowidth = false
    wb = p.workbook
    styles = ApplicationDocument.xlsx_styles(wb)
    columns = ['Identifier Backend', *TRANSLATED_LANGS.collect(&:to_s).collect(&:upcase)]
    column_title_styles = columns.collect{|col| styles[:h1] }
    column_styles = columns.collect{|col| styles[:standard] }
    wb.add_worksheet(name: Rails.application.class.parent_name) do |sheet|
      sheet.add_row columns, style: column_title_styles
      sheet.column_widths *[80, *TRANSLATED_LANGS.collect{ 40 }]

      sheet.sheet_view.pane do |pane|
        # lock first row
        pane.top_left_cell = "A2"
        pane.state = :frozen
        pane.x_split = 0
        pane.y_split = 1
        pane.active_pane = :bottom_right
      end

      data.collect do |k,v|
        sheet.add_row [k, *TRANSLATED_LANGS.collect{|l| v[l]||''}], style: column_styles
      end
    end
    p.use_shared_strings = true
    p.serialize(filename)
  end

  def self.update_locales!(data: get_remote_data, overwrite: false)
    TRANSLATED_LANGS.each do |lang|
      next unless I18n.locale_available?(lang)
      lang_data = data.dup
      # extract the specific lang value
      lang_data.each do |k,v|
puts "-"*80
puts "#{lang} #{k} #{v.inspect}"
        lang_data[k] = v[lang] || ''
      end
      yaml_name = "config/locales/_new_#{lang}.yml"
      yaml_name = "config/locales/#{lang}.yml" if overwrite
      { lang.to_s => unflatten_hash(lang_data) }.to_yaml.gsub(/^---\n/,'').to_file yaml_name
    end
  end

end