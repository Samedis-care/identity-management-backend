class OpenapiSpecsController < ActionController::Base

  require "#{Rails.root}/lib/generators/openapi_spec/lib/helpers"

  def show
    @specs = OpenapiSpec::Helpers.available_specs

    render 'openapi_specs/show'
  end

end
