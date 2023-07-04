class Role < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  field :actors_app_id, type: BSON::ObjectId
  field :app, type: String

  field :title, type: String, localize: true
  field :description, type: String, localize: true

  field :name, type: String
  field :write_protected, type: Boolean, default: false # write_protected can't be changed but deleted
  field :system, type: Boolean, default: false # system records can't be changed or deleted

  QUICKFILTER_COLUMNS = [:title, :description]
  search_in *QUICKFILTER_COLUMNS

  belongs_to :actors_app, class_name: 'Actors::App'
  has_and_belongs_to_many :functionalities # this creates functionality_ids on the actor
  has_many :actors, foreign_key: :role_ids

  index functionality_ids: 1
  index actors_app_id: 1
  index({ name: 1}, { background:true, unique: true, name: 'role_name_unique' })
  index deleted: 1

  def validate_presence_for_languages
    [:en]
  end

  before_validation :safe_name!

  before_validation do |record|
    self.actors_app ||= Actors::App.named(self.app).first
    self.title ||= self.name
    self.description ||= self.title
  end

  before_save if: :is_write_protected? do |record|
    errors.add :write_protected, 'protection flag set'
    throw(:abort)
  end

  before_destroy if: :is_system_protected? do |record|
    errors.add :system, 'protection flag set'
    throw(:abort)
  end

  after_save :update_group_candos!, if: :functionality_ids_previously_changed?

  def self.system_override
    @@system_override ||= false
  end
  def self.system_override=(v)
    @@system_override = !!v
  end
  def system_override
    @system_override ||= @@system_override ||= false
  end
  def system_override=(v)
    @system_override = !!v
  end
  def is_system_protected?
    system? && !system_override
  end
  def is_write_protected?
    write_protected && write_protected_was && !system_override
  end

  class LocaleSchema

    def self.schema(app)
      raise "Schema is app specific you need to pass an App as argument" unless app.is_a?(Actors::App)
      {
        type: :object,
        additionalProperties: false,
        minProperties: 1,
        patternProperties: {
          Regexp.new("^#{app.languages.join('|')}$") => {
            type: :object,
            additionalProperties: false,
            patternProperties: {
              additionalProperties: false,
              minProperties: 1,
              /[a-z0-9\-_]+/ => { # regex matches role name
                uniqueItems: true,
                type: :object,
                properties: {
                  title: { anyOf: [{ type: :string }, { type: :null }] },
                  description: { anyOf: [{ type: :string }, { type: :null }] }
                }
              }
            }
          }
        }
      }
    end
  end

  class SeedSchema
    def self.schema(app)
      raise "Schema is app specific you need to pass an App as argument" unless app.is_a?(Actors::App)
      {
        type: :object,
        additionalProperties: false,
        #required: [:app, :name, :title, :description, :candos],
        properties: {
          app: {
            type: :string,
            required: true,
            minLength: 1,
            enum: [app.name]
          },
          name: {
            type: :string,
            required: true,
            minLength: 1
          },
          title: {
            type: :string,
            required: true,
            minLength: 1
          },
          description: {
            type: :string,
            required: true,
            minLength: 1
          },
          candos: {
            type: :array,
            minItems: 0,
            uniqueItems: true,
            required: true,
            items: {
              type: :string,
              pattern: app.cando_regex
            }
          }
        }
      }
    end
  end

  # Constructs a hash that when turned into yaml
  # representing an importable role record
  # used by Actors::App to create a dump of all
  # roles of an app.
  def seed_dump
    {
      app: actors_app.name,
      name: name,
      title: title_translations.dig(:en),
      description: description_translations.dig(:en),
      candos: candos
    }.stringify_keys
  end

  # Constructs a hash in the format for locale yaml
  # including all languages supported by the app.
  # used by Actors::App to create locale files
  def locale_dump
    actors_app.translations.collect do |l, _|
      [l, {
        name.to_s => {
          "title" => title_translations.dig(l),
          "description" => description_translations.dig(l)
        }
      }]
    end.to_h
  end

  def candos
    functionalities.collect(&:cando).sort
  end

  def update_group_candos!
    _mappings = Actors::Mapping.where(:parent_ids.in => actors.pluck(:_id))
    _mappings.merge_group_candos!
    User.where(:_id.in => _mappings.distinct(:user_id)).cache_expire!
  end

  # ensure nice names
  def safe_name!
    self.name = self.title if self.name.blank?
    self.name = self.name.to_slug
  end

end
