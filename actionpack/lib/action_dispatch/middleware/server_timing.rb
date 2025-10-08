# frozen_string_literal: true

# :markup: markdown

require "active_support/notifications"

module ActionDispatch
  class ServerTiming
    class Subscriber # :nodoc:
      include Singleton
      KEY = :action_dispatch_server_timing_events

      def initialize
        @mutex = Mutex.new
      end

      def call(event)
        if events = ActiveSupport::IsolatedExecutionState[KEY]
          events << event
        end
      end

      def collect_events
        events = []
        ActiveSupport::IsolatedExecutionState[KEY] = events
        yield
        events
      ensure
        ActiveSupport::IsolatedExecutionState.delete(KEY)
      end

      def ensure_subscribed
        @mutex.synchronize do
          # Subscribe to all events, except those beginning with "!" Ideally we would be
          # more selective of what is being measured
          @subscriber ||= ActiveSupport::Notifications.subscribe(/\A[^!]/, self)
        end
      end

      def unsubscribe
        @mutex.synchronize do
          ActiveSupport::Notifications.unsubscribe @subscriber
          @subscriber = nil
        end
      end
    end

    def self.unsubscribe # :nodoc:
      Subscriber.instance.unsubscribe
    end

    # ActionDispatch ServerTiming.
    #
    # This middleware is added to the stack when `config.server_timing = true`
    # or `config.server_timing = :runtime_only` is set in your application configuration
    def initialize(app, mode)
      @app = app
      @mode = mode

      unless @mode == :runtime_only
        @subscriber = Subscriber.instance
        @subscriber.ensure_subscribed
      end
    end

    def call(env)
      if @mode == :runtime_only
        runtime_only_timing(env)
      else
        detailed_timing(env)
      end
    end

    private
      def runtime_only_timing(env)
        response = @app.call(env)

        if timing_value = extract_runtime_value(headers)
          set_timing_header(response[1], timing_value)
        end

        response
      end

      def detailed_timing(env)
        response = nil
        events = @subscriber.collect_events { response = @app.call(env) }

        set_timing_header(response[1], detailed_timing_value(events))

        response
      end

      def set_timing_header(headers, new_value)
        if headers[server_timing_header].present?
          headers[server_timing_header] = "#{headers[server_timing_header]}, #{new_value}"
        else
          headers[server_timing_header] = new_value
        end
      end

      def extract_runtime_value(headers)
        # Rack::Runtime sets X-Runtime header in seconds (e.g., "0.017117")
        # Convert to Server-Timing format: "total;dur=17.12" (milliseconds)
        if runtime = headers["x-runtime"]
          duration_ms = runtime.to_f * 1000
          "total;dur=%.2f" % duration_ms
        end
      end

      def detailed_timing_value(events)
        events.group_by(&:name).map do |event_name, events_collection|
          "%s;dur=%.2f" % [event_name, events_collection.sum(&:duration)]
        end.join(", ")
      end

      def server_timing_header
        ActionDispatch::Constants::SERVER_TIMING
      end
  end
end
