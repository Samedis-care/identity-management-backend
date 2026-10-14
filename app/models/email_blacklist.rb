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

  # The lookup is a case-sensitive exact match, and the address it is compared with is
  # downcased and stripped by Devise. An entry therefore only matches when it is stored in
  # that same form (Samedis-care/samedis-care-issues#3289) -- always store it normalised.
  before_validation { self.domain = self.class.normalize_domain(domain) unless domain.nil? }

  validates_uniqueness_of :domain

  before_save do |record|
  end

  def self.normalize_domain(domain)
    domain.to_s.strip.downcase
  end

  def self.validate(email)
    domain = normalize_domain(email.to_s.split('@').last)
    return false if domain.blank?
    where(active: true, domain: domain).count.eql?(0)
  end

  def self.import_list(blacklist_file)
    File.foreach(blacklist_file).with_index do |line, line_num|
      domain = normalize_domain(line)
      where(domain: domain).first_or_create unless domain.blank? || domain.start_with?('#')
    end
  end

end
