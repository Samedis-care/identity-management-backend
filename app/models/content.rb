class Content < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  extend Enumerize

  belongs_to :actors_app, optional: true, class_name: 'Actors::App'

  field :app, type: String
  field :actors_app_id, type: BSON::ObjectId
  enumerize :name, in: %i(tos privacy tos-privacy app-info)
  field :name, type: String
  field :content, type: String, localize: true

  # obsolete with localize above, remove after frontend localization is on master
  field :content_de, type: String
  field :content_en, type: String

  field :version, type: Integer
  field :acceptance_required, type: Boolean, default: true
  field :active, type: Boolean, default: true

  index({ app: 1, name: 1, version: -1 }, { sparse: true, unique: true, name: 'contents' })

  index app: 1
  index actors_app_id: 1
  index name: 1
  index version: 1
  index acceptance_required: 1, active: 1, app: 1, name: 1

  QUICKFILTER_COLUMNS = [:app, :name, :version, :content]
  search_in *QUICKFILTER_COLUMNS

  validates :name, uniqueness: {
    scope: [:app, :version],
    message: Proc.new { I18n.t('mongoid.errors.models.content.attributes.name.uniqueness') }
  }

  validates_presence_of :app, :name, :content, :version #:content_de, :content_en,

  before_validation do
    self.app = self.app.to_slug
    self.actors_app ||= Actors::App.named(self.app).first
    self.name = self.name.to_slug
    self.version ||= self.class.where(name: self.name).count + 1
  end

  def user
    @user
  end
  def user=(v)
    @user = v
  end

  def content_de=(v)
    raise "deprecated field, use content_translations[:de]"
  end
  def content_en=(v)
    raise "deprecated field, use content_translations[:en]"
  end

  def self.latest
    collection.aggregate([
      { 
        '$match': {
          active: true
        }.merge(criteria.selector)
      },
      { 
        '$sort': { version: -1 }
      },
      {
        '$group': {
          _id: '$name',
          version: { '$max': '$version' },
          content_id: { '$first': '$_id' }
        }
      }
    ])
  end

  def self.acceptable(app)
    collection.aggregate([
      { "$match" => {
          "app" => app,
          "acceptance_required" => true,
          "active" => true
        }
      }, { 
        "$sort" => { value: -1 }
      }, {
        "$group" => {
          "_id" => "$name",
          "content" => { "$first" => "$$ROOT" }
        }
      }, {
        "$replaceRoot" => { newRoot: "$content" }
      }
    ])
  end

  # Determines existing contents that require versioned acceptance
  # @return {Hash} with the name of Content as key and highest existing version
  def self.acceptance_required(app)
    acceptances_required[app] || {}
  end

  # Determines existing contents for all apps that require versioned acceptance
  # @return {Hash} with the name of APP as key and Hash with name/highest-version
  def self.acceptances_required
    collection.aggregate([
      { "$match" => {
          "acceptance_required" => true,
          "active" => true
        },
      }, {
       "$group" => {
          "_id" => { "app" => "$app", "name" => "$name" },
          "version" => { "$max" => "$version" }
        }
      }
    ]).to_a.inject({}) do |hsh, c|
      app, name, version = c['_id']['app'], c['_id']['name'], c['version']
      (hsh[app] ||= {}).merge!({ name => version })
      hsh
    end
  end

end
