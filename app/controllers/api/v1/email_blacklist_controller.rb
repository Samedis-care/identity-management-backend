class Api::V1::EmailBlacklistController < Api::V1::JsonApiController

  MODEL_BASE = EmailBlacklist
  MODEL = EmailBlacklist.all
  MODEL_OVERVIEW = EmailBlacklist.all
  SERIALIZER = EmailBlacklistSerializer
  OVERVIEW_SERIALIZER = EmailBlacklistSerializer

  SWAGGER = { tag: 'Email Blacklist', name: 'Email Blacklist', header: 'Manage blocked email domains' }

  PERMIT_UPDATE = %i[domain active].freeze
  PERMIT_CREATE = PERMIT_UPDATE

  private
  def cando
    CANDO.merge({
      show:    %w(identity-management/global.admin+identity-management/email-blacklists.reader),
      index:   %w(identity-management/global.admin+identity-management/email-blacklists.reader),
      create:  %w(identity-management/global.admin+identity-management/email-blacklists.writer),
      update:  %w(identity-management/global.admin+identity-management/email-blacklists.writer),
      destroy: %w(identity-management/global.admin+identity-management/email-blacklists.deleter)
    })
  end

end
