class EmailBlacklist < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  field :domain, type: String
  field :active, type: Boolean, default: true

  index active: 1
  index({ domain: 1 }, { unique: true, name: 'email_blacklist' })

  QUICKFILTER_COLUMNS = [:domain]
  search_in *QUICKFILTER_COLUMNS

  validates_uniqueness_of :domain

  before_save do |record|
  end

  def self.validate(email)
    domain = email.to_s.split('@').last
    return false if domain.blank?
    where(active: true, domain: domain).count.eql?(0)
  end

  def self.import_list(blacklist_file)
    File.foreach(blacklist_file).with_index do |line, line_num|
      domain = line.strip
      where(domain: domain).first_or_create unless domain.blank? || domain.start_with?('#')
    end
  end

end
