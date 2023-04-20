class Functionality < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  field :actors_app_id, type: BSON::ObjectId

  field :title, type: String, localize: true
  field :description, type: String, localize: true

  field :app, type: String
  field :module, type: String
  field :ident, type: String
  field :quickfilter, type: Array

  index actors_app_id: 1
  index({ app: 1, module: 1, ident: 1 }, { background: true, sparse: true, unique: true, name: 'functionalities' })
  index deleted: 1

  QUICKFILTER_COLUMNS = [:title, :description, :app, :module, :ident]
  search_in *QUICKFILTER_COLUMNS

  belongs_to :actors_app, class_name: 'Actors::App'
  has_and_belongs_to_many :roles # this creates role_ids on here

  validates :title, presence: true
  validates :description, presence: true

  def validate_presence_for_languages
    [:en]
  end

  validates_presence_of :module
  validates_presence_of :ident
  validates_presence_of :actors_app
  validates :ident, uniqueness: {
    scope: [:app, :module],
    message: Proc.new { I18n.t('mongoid.errors.models.functionality.attributes.ident.uniqueness') }
  }

  before_validation do |record|
    self.actors_app ||= Actors::App.named(self.app).first || Actors::App.im
    self.title ||= self.cando
    self.description ||= self.title
  end

  before_save do |record|
    self.app ||= self.actors_app&.name
    self.app = self.app.to_slug if self.app.present?
    self.module = self.module.to_slug
    self.ident = self.ident.to_slug
    self.quickfilter = record.attributes.collect{|a,v| Functionality::QUICKFILTER_COLUMNS.include?(a.to_sym) ? v : nil }.compact.uniq
  end

  # Seed candos or updates title and description from seed file
  # Most important is to execute `Role.seed!` before or after 
  # so the candos are actually in use.
  def self.seed!
    puts "=" *80
    YAML::load_file(Rails.root.join('db', 'seeds', 'candos.yml')).each do |f|
      f = f.with_indifferent_access
      _attributes = {}
      _current_locale = I18n.locale

      if f[:title_translations].is_a?(Hash)
        _attributes[:title_translations] = f[:title_translations]
      else
        # translate with current yml translation if available
        _title_translations = I18n.available_locales.collect do |l|
          I18n.locale = l
          [l, Functionality.new.translate_me(:title, f[:title])]
        end.to_h
        _attributes[:title_translations] = _title_translations
      end
      if f[:description_translations].is_a?(Hash)
        role.attributes = { description_translations: f[:description_translations] }
      else
        # translate with current yml translation if available
        _description_translations = I18n.available_locales.collect do |l|
          I18n.locale = l
          [l, Functionality.new.translate_me(:description, f[:description])]
        end.to_h
        _attributes[:description_translations] = _description_translations
      end
      Functionality.available.cando(f[:cando]).first_or_create.update_attributes(_attributes)
      I18n.locale = I18n.default_locale
      puts "Cando: #{f[:cando]}"
    end
    puts "=" *80
    puts "Seeding Candos done!"
    puts "=" *80
  end

  # @return {String} cando format of the functionality (human readable)
  def cando
    "#{self.app.to_slug}/#{self.module}.#{self.ident}"
  end

  # Used to show selected values
  def display
    "(#{self.app.to_slug}/#{self.module}.#{self.ident}) #{self.title} #{self.description}"
  end

  # Find exact Functionality by cando
  # @param s {String} cando (e.g. "app/module.ident")
  def self.get_cando(s)
    cando(s).first
  end

  # Criteria Helper to find a Functionality
  # by cando string.
  def self.cando(s)
    a, m = s.split('/', 2)
    m, i = m.split('.', 2)
    where(app: a.to_slug, module: m, ident: i)
  end

  # Criteria Helper to find multiple Functionalities by an array of candos
  # @param cando_list {Array} of candos
  def self.with_any_of(cando_list)
    funcs = cando_list.map do |s|
      a, m = s.split('/', 2)
      m, i = m.split('.', 2)
      { app:a.to_slug, module: m, ident: i }
    end
    Functionality.or(funcs)
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
              app.cando_regex => {
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
        required: [:cando, :title, :description],
        properties: {
          cando: {
            type: :string,
            pattern: app.cando_regex
          },
          title: {
            type: :string,
            minLength: 1
          },
          description: {
            type: :string,
            minLength: 1
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
      cando: cando,
      title: title_translations.dig(:en),
      description: description_translations.dig(:en)
    }.stringify_keys
  end

  # Constructs a hash in the format for locale yaml
  # including all languages supported by the app.
  # used by Actors::App to create locale files
  def locale_dump
    actors_app.translations.collect do |l, _|
      [l, {
        cando.to_s => {
          "title" => title_translations.dig(l),
          "description" => description_translations.dig(l)
        }
      }]
    end.to_h
  end

end
