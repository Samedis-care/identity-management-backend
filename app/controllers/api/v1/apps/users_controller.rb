class Api::V1::Apps::UsersController < Api::V1::JsonApiController

  MODEL_BASE = User
  MODEL = -> {
    current_app_actor.users.available.includes(:actor)
  }
  MODEL_OVERVIEW  = -> {
    current_app_actor.users.available
  }
  SERIALIZER = AppUserSerializer
  OVERVIEW_SERIALIZER = UserOverviewSerializer

  PERMIT_UPDATE = [
    :image_b64,
    :image,
    :pwd_reset_uid,
    :active,
    :email,
    :picture,
    :locale,
    :set_password,
    :new_password,
    :new_password_verify,
    :title,
    :first_name,
    :last_name,
    :short,
    :gender,
    :invalid_at
  ]

  undef_method :create

  # this will not delete the user (the login) but all mappings under the current_app
  # to essentially remove the user from every tenant below the app
  def destroy
    users = records_destroy
    users.to_a.each do |user|
      current_app_actor.descendants.mappings.where(map_actor_id: user.actor_id).delete_all
      user.cache_expire!
    end
    render_jsonapi_msg({
      success: true,
      error: nil,
      message: nil,
      error_details: nil
    }, 200)
  end

  private
  def cando
    CANDO.merge({
      show:    %w(~/apps.admin+identity-management/users.reader),
      index:   %w(~/apps.admin+identity-management/users.reader),
      update:  %w(~/apps.admin+identity-management/users.writer),
      destroy:  %w(~/apps.admin+identity-management/users.writer)
    })
  end

end
