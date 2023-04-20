class Api::V1::AccessControl::App::GroupsController < Api::V1::AccessControl::Apps::GroupsController

  def index
    _app = ::Actors::App.named(params_json_api[:name]).first
    determine = self.class::MODEL.for_app(_app.id)
    respond_to do |format|
      format.any {
        render_serialized_records(
          records: determine,
          total: determine.count
        )
      }
    end
  end

end
