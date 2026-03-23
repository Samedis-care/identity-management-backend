class OpenapiSpecsController < ActionController::Base

  require "#{Rails.root}/lib/generators/openapi_spec/lib/helpers"

  def show
    @specs = OpenapiSpec::Helpers.available_specs
    @current_spec_url = @specs.find { |s|
      s[:version] == params[:version] && s[:name] == params[:spec]
    }&.dig(:url) || @specs.first&.dig(:url)

    render 'openapi_specs/show'
  end

end
