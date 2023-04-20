module Actors

  class ContainerEnterprises < Actor

    def insertable_child_types
      %i[enterprise]
    end

  end

end
