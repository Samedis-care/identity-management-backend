module WithBlameNoIndex
  extend ActiveSupport::Concern

  included do
    include Mongoid::Changeable

    field :created_by, type: BSON::ObjectId
    field :created_by_user, type: String
    field :updated_by, type: BSON::ObjectId
    field :updated_by_user, type: String

    BLAME_COLUMNS ||= {
        created_by_user: :standard,
        created_at: ->(v){ v.present? ? v.strftime(I18n.t('date.formats.short')) : '' },
        updated_by_user: :standard,
        updated_at: ->(v){ v.present? ? v.strftime(I18n.t('date.formats.short')) : '' }
    }

    before_save do
      if editing_user.present? && changes.any?
        if new_record?
          self.created_by = BSON::ObjectId(editing_user.dig(:id))
          self.created_by_user = editing_user.dig(:username)
        else
          self.updated_by = BSON::ObjectId(editing_user.dig(:id))
          self.updated_by_user = editing_user.dig(:username)
          Changelog.log_record! self
        end
      end
    end

    def self.exportable_columns
      super.merge(self::BLAME_COLUMNS)
    end
  end

  def editing_user=(_user)
    @editing_user = _user.to_h
  end

  def editing_user
    @editing_user || nil
  end
end
