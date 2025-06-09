# frozen_string_literal: true

module ActiveSupport
  module Testing
    # ReplicationCoordinator is a test helper implementing
    # ActiveSupport::ReplicationCoordinator::Base that can be used to test the behavior of objects
    # that depend on replication state.
    class ReplicationCoordinator < ActiveSupport::ReplicationCoordinator::Base
      # Returns the number of times #fetch_active_zone has been called.
      attr_reader :fetch_count

      # Initializes the replication coordinator with an initial active zone state.
      #
      # The replication coordinator can be initialized with an initial active zone state using the
      # optional +active_zone+ parameter, which defaults to +true+.
      def initialize(active_zone = true, **options)
        @next_active_zone = active_zone
        @fetch_count = 0
        super(**options)
      end

      # Sets the value that will next be returned by #fetch_active_zone, simulating an external
      # replication state change.
      def set_next_active_zone(active_zone)
        @next_active_zone = active_zone
      end

      def fetch_active_zone # :nodoc:
        @fetch_count += 1
        @next_active_zone
      end
    end
  end
end
