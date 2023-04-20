class ContentAcceptanceSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute(:acceptance_given) do |record|
    if record.acceptance_required?
      if record.user.present?
        !record.user.acceptance_required?(record)
      else
        nil
      end
    else
      false
    end
  end

  attribute(:acceptance_required) do |record|
    unless record.user.is_a?(User)
      false
    else
      record.acceptance_required
    end
  end

  attributes(
    :app,
    :name,
    :version,
    :content_translations,
    :acceptance_required,
    :created_at,
    :updated_at)

  class Schema < JsonApi::Schema

    def schema_record
      Proc.new {
        string :id, description: 'unique record id'
        string :type, default: 'content', description: 'defines the class of the data'

        object :attributes, description: 'the main attributes of this record' do
          string :id, description: 'unique record id'
          string :actors_app_id, description: 'id of the app this content belongs to'
          string :name, default: 'app-name', description: 'name of the content (like "tos", "app-info")'
          number :version, description: 'highest active-flagged version will be used'
          object :content_translations, description: 'Hash of locale-languages with translated content' do
            string :de, default: 'Deutsche Übersetzung', description: 'German content'
            string :en, default: 'English translation', description: 'English content'
          end
          boolean :active, default: false, description: 'only active flagged will be used, leave inactive during draft'
          boolean :acceptance_required, default: false, description: 'when true the user is required to accept every new version of this content'
          boolean :acceptance_given, default: false, description: 'if required indicates if it was yet given by the current user'
        end
      }
    end

  end

end
