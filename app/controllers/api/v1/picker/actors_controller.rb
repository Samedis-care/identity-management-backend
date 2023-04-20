module Api::V1::Picker
  class ActorsController < Api::V1::JsonApiController

    MODEL_BASE = Actor
    MODEL = Actor.available
    SERIALIZER = ActorSerializer
    OVERVIEW_SERIALIZER = ActorOverviewSerializer

    undef_method :create
    undef_method :update
    undef_method :destroy

    private
    def model_index
      self.class::MODEL.not.mappings_and_users.reorder(short_name: 1)
    end
    def model_show
      self.class::MODEL.not.mappings_and_users
    end

    def cando
      CANDO.merge({
        index:   %w(identity-management/actors.reader),
        show:    %w(identity-management/actors.reader)
      })
    end

  end
end
