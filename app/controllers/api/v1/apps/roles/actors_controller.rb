class Api::V1::Apps::Roles::ActorsController < Api::V1::JsonApiController

  MODEL_BASE = Actor
  MODEL = -> {
    role.actors
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = ActorSerializer
  OVERVIEW_SERIALIZER = ActorOverviewSerializer

  #PERMIT_CREATE = []

  undef_method :create
  undef_method :update
  undef_method :destroy

  private

  def role
    current_app_actor.roles.find(params[:role_id])
  end

  def cando
    CANDO.merge({
      show:   %w(~/apps.admin+identity-management/roles.reader+identity-management/actors.reader),
      index:   %w(~/apps.admin+identity-management/roles.reader+identity-management/actors.reader)
    })
  end

end
