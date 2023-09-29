# make this log spam STFU once and for all
module Mongo
  class Monitoring

    # silence this
    class TopologyChangedLogSubscriber < SDAMLogSubscriber

      private

      def log_event(event)
        # if event.previous_topology.class != event.new_topology.class
        #   log_debug(
        #     "Topology type '#{event.previous_topology.display_name}' changed to " +
        #     "type '#{event.new_topology.display_name}'."
        #   )
        # else
        #   log_debug(
        #     "There was a change in the members of the '#{event.new_topology.display_name}' " +
        #       "topology."
        #   )
        # end
      end
    end
    # end of class

    # silence that too
    class ServerDescriptionChangedLogSubscriber < SDAMLogSubscriber

      private

      def log_event(event)
        # log_debug(
        #   "Server description for #{event.address} changed from " +
        #   "'#{event.previous_description.server_type}' to '#{event.new_description.server_type}'#{awaited_indicator(event)}."
        # )
      end

      def awaited_indicator(event)
        # if event.awaited?
        #   ' [awaited]'
        # else
        #   ''
        # end
      end
    end
    # end of class
  end
end
