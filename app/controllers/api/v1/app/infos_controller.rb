class Api::V1::App::InfosController < Api::V1::JsonApiController

  MODEL_BASE = Actors::App
  SERIALIZER = AppInfoSerializer

  SWAGGER = {
    tag: 'App Info',
    show: 'Loads app info identified by name'
  }

  skip_before_action :authenticate_user!, only: [:show]
  skip_before_action :authorize, only: [:show]

  undef_method :index
  undef_method :destroy
  undef_method :update
  undef_method :create


  def record_show
    ::Actors::App.named(params_json_api[:name]).only(:system, :name, :short_name, :full_name, :url, :image_data, :config).first
  end

end
