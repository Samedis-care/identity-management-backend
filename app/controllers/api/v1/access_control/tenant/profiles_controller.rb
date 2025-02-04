class Api::V1::AccessControl::Tenant::ProfilesController < Api::V1::JsonApiController

  PAGE_LIMIT = 100
  PAGE_LIMIT_MAX = 100

  MODEL_BASE = Actors::Group
  MODEL = -> {
    current_tenant_actor.profiles.available
  }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = GroupActorSerializer
  OVERVIEW_SERIALIZER = GroupActorSerializer

  SWAGGER = {
    tag: 'Access Control',
    action_suffix: 'Custom profiles'
  }.freeze

  PERMIT_CREATE = [
    :title,
    :name,
    {
      title_translations: {},
      role_ids: []
    }
  ].freeze
  PERMIT_UPDATE = PERMIT_CREATE

  private

  def cando
    CANDO.merge({
      show:    %w(~/access-control.reader),
      index:   %w(~/access-control.reader),
      create:  %w(~/access-control.writer),
      update:  %w(~/access-control.writer),
      destroy: %w(~/access-control.writer)
    })
  end

end
