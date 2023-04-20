class Api::V1::Apps::Users::UserController < Api::V1::JsonApiController
  def target_user_id
    params[:user_id]
  end

  def target_user
    @target_user ||= User.find(target_user_id)
  end
end
