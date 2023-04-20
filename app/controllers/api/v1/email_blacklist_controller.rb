class Api::V1::EmailBlacklistController < Api::V1::JsonApiController

  MODEL_BASE = EmailBlacklist
  MODEL = EmailBlacklist.all
  MODEL_OVERVIEW = EmailBlacklist.all
  SERIALIZER = EmailBlacklistSerializer
  OVERVIEW_SERIALIZER = EmailBlacklistSerializer

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

  def params_update
    params.fetch(:data, {}).permit(:domain, :active)
  end
  def params_create
    params_update
  end

end
