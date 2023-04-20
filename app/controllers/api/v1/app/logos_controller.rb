class Api::V1::App::LogosController < Api::V1::JsonApiController

  skip_before_action :authenticate_user!, only: [:show]
  skip_before_action :authorize, only: [:show]

  undef_method :index
  undef_method :destroy
  undef_method :update
  undef_method :create

  def show
    app = Actor.apps.named(params_json_api[:name]).only(:image_data).first
    if app&.image&.present?
      redirect_to app.image.dig(:large).url
    else
      render plain: nil, status: 404
    end
  end

end
