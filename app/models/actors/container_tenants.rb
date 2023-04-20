module Actors

  class ContainerTenants < Actor

    def insertable_child_types
      %i[tenant]
    end


  end

end
