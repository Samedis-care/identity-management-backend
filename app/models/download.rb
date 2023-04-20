class Download < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  Shrine.plugin :mongoid
  include DownloadUploader::Attachment.new(:file)

  belongs_to :user
  field :name, type: String
  field :file_data, type: Hash
  field :expires_at, type: DateTime

  index({ name: 1 })

  QUICKFILTER_COLUMNS = [:name]
  search_in *QUICKFILTER_COLUMNS

  before_create do |record|
    self.class.expired.for_user(record.user).destroy_all
    record.expires_at ||= 1.month.from_now
  end

  def self.available
    all.not.expired
  end

  def self.expired
    where(expires_at:{'$lt'=>Time.now})
  end

  def self.for_user(user)
    where(user: user)
  end

end
