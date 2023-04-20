module MongoDB
  module Instrumentation
    class CommandSubscriber

      attr_reader :requests

      def initialize
        @requests = {}
      end

      def started(event)
        # @type [Sentry::Span] span
        span = Sentry.get_current_scope&.get_transaction&.start_child(op: 'mongodb.' + event.command_name)
        if span
          span.set_tag('component', 'ruby-mongodb')
          span.set_tag('db.instance', event.database_name)
          span.set_data('db.statement', event.command)
          span.set_tag('db.type', 'mongo')
          span.set_tag('span.kind', 'client')
          # extra info
          span.set_tag('mongo.command.name', event.command_name)
          span.set_data('mongo.operation.id', event.operation_id)
          span.set_data('mongo.request.id', event.request_id)
        end

        @requests[event.request_id] = span
      end

      def succeeded(event)
        return if @requests[event.request_id].nil?

        # tag the reported duration, in case it differs from what we saw
        # through the notifications times
        # @type [Sentry::Span] span
        span = @requests[event.request_id]
        span.set_data('took.ms', event.duration * 1000)

        span.finish
        @requests.delete(event.request_id)
      end

      def failed(event)
        return if @requests[event.request_id].nil?

        # tag the reported duration and any error message that came through
        # @type [Sentry::Span] span
        span = @requests[event.request_id]
        span.set_data('took.ms', event.duration * 1000)
        span.set_status('error')
        span.set_data('error_message', event.message)

        span.finish
        @requests.delete(event.request_id)
      end
    end
  end
end

Mongo::Monitoring::Global.subscribe(Mongo::Monitoring::COMMAND, MongoDB::Instrumentation::CommandSubscriber.new)