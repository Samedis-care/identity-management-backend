class Api::V1::AccessControl::Apps::GroupsController < Api::V1::JsonApiController

  PAGE_LIMIT = 100
  PAGE_LIMIT_MAX = 100

  MODEL_BASE = AccessControl
  MODEL = ::AccessControl
  MODEL_OVERVIEW = ::AccessControl
  SERIALIZER = AccessControlSerializer
  OVERVIEW_SERIALIZER = AccessControlSerializer

  SWAGGER = {
    tag: 'Access Control',
    action_suffix: 'available groups for this app'
  }

  undef_method :update
  undef_method :create
  undef_method :show
  undef_method :destroy

  def index
    determine = self.class::MODEL.for_app(current_app_id)
    respond_to do |format|
      format.any {
        render_serialized_records(
          records: determine,
          total: determine.count
        )
      }
    end
  end

  private

  def cando
    CANDO.merge({
      index:  %w(identity-management/global.admin ~/access-control.reader ~/notifications.writer)
    })
  end

end
