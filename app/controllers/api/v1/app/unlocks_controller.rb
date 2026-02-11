class Api::V1::App::UnlocksController < Devise::UnlocksController
  skip_before_action :verify_authenticity_token

  def show
    self.resource = resource_class.unlock_access_by_token(params[:unlock_token])

    user = resource_class.where(id: resource.id).first
    login_url = URI.parse(User.redirect_url_login(params[:app]))
    login_url.query = URI.encode_www_form({ emailHint: user&.email }.compact)

    redirect_to login_url, allow_other_host: true
  end
end
