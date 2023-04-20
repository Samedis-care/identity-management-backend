module Actors

  class ContainerUsers < Actor

    def insertable_child_types
      %i[user]
    end

  end

end
