class Api::Admin::GcStatsController < Api::V1::JsonApiController
  def index
    render_jsonapi_msg({
      gc: GC.stat,
      objects: ObjectSpace.count_objects
    })
  end

  private

  def cando
    { index: %w(identity-management/global.admin) }
  end
end
