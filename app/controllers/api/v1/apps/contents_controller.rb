class Api::V1::Apps::ContentsController < Api::V1::JsonApiController

  MODEL_BASE = Content
  MODEL = -> {
    Content.where(actors_app_id: current_app_id)
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = ContentSerializer
  OVERVIEW_SERIALIZER = ContentSerializer

  skip_before_action :authenticate_user!, only: :show
  skip_before_action :authorize, only: :show

  private
  def cando
    CANDO.merge({
      show:    %w(public),
      index:   %w(~/apps.admin+identity-management/contents.reader),
      create:  %w(~/apps.admin+identity-management/contents.writer),
      update:  %w(~/apps.admin+identity-management/contents.writer),
      destroy: %w(~/apps.admin+identity-management/contents.deleter)
    })
  end

  def params_update
    params.fetch(:data, {}).permit(:name, :active, :acceptance_required, :content_translations => {})
  end
  def params_create
    params_update.merge({actors_app_id: current_app_id, app: current_app_actor.name.to_s.gsub(/\_/,'-').to_slug})
  end

end
