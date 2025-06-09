# frozen_string_literal: true

require "active_support/concurrency/share_lock"

module ActiveSupport
  # = Active Support Replication Coordinator
  #
  # Provides an interface for responding to changes in active/passive state across multiple
  # availability zones.
  #
  # == Replication, Availability Zones, and Active-Passive State
  #
  # A common deployment topology for Rails applications is to have application servers running in
  # multiple availability zones, with a single database that is replicated across these zones.
  #
  # In such deployment, application code may need to determine whether it is running an "active"
  # zone and is responsible for writing to the database, or in a "passive" or "standby" zone that
  # primarily reads from the zone-local database replica. And, in case of a zone failure, the
  # application may need to dynamically promote a passive zone to become the active zone.
  #
  # The term "Passive" here is intended to include deployments in which the non-active zones are
  # handling read requests, and potentially even performing occasional writes back to the active
  # zone over an inter-AZ network link. The exact interpretation depends on the nature of the
  # replication strategy and your deployment topology.
  #
  # Some example scenarios where knowing the replication state is important:
  #
  # - Custom database selector middleware
  # - Controlling background jobs that should only run in an active zone
  # - Deciding whether to preheat fragment caches for "next page" paginated results (which may not
  #   be cached in time if relying on an inter-AZ network link and replication lag).
  #
  # The two classes provided by this module are:
  #
  # - ReplicationCoordinator::Base: An abstract base class that provides a monitoring
  #   mechanism to fetch and cache the replication state on a configurable time interval and notify
  #   when that state changes.
  # - ReplicationCoordinator::SingleZone: A concrete implementation that always
  #   indicates an active zone, and so it represents the default behavior for a single-zone
  #   deployment that does not use database replication.
  #
  # == Custom Replication Coordinators
  #
  # By default, every Rails application is configured to use the SingleZone replication
  # coordinator. To configure Rails to use your own replication coordinator, first create a class
  # that subclasses ActiveSupport::ReplicationCoordinator::Base:
  #
  #   class CustomReplicationCoordinator < ActiveSupport::ReplicationCoordinator::Base
  #     def fetch_active_zone
  #       # Custom logic to determine if the local zone is active and return a boolean
  #     end
  #   end
  #
  # Then configure Rails with an initializer:
  #
  #   Rails.application.configure do
  #     config.before_initialize do
  #       config.replication_coordinator = CustomReplicationCoordinator.new(polling_interval: 2.seconds)
  #     end
  #   end
  #
  # == Development and Auto-reloading
  #
  # The replication coordinator is loaded once and is not monitored for changes. You will have to
  # restart the server for changes to be reflected in a running application.
  #
  # For testing the behavior of code during active/passive state changes, please see the test helper
  # class ActiveSupport::Testing::ReplicationCoordinator.
  module ReplicationCoordinator
    # = Replication Coordinator Abstract Base Class
    #
    # An abstract base class that provides a monitoring mechanism to fetch and cache the replication
    # state on a configurable time interval and notify when that state changes.
    #
    # Subclasses must only implement #fetch_active_zone, which returns a boolean indicating whether
    # the caller is in an active zone. This method may be expensive, so the class uses a
    # {Concurrent::TimerTask}[https://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/TimerTask.html]
    # to manage a background thread o periodically check (and cache) this value. The current cached
    # status can cheaply be inspected with #active_zone?. The refresh interval can be set by passing
    # a +polling_interval+ option to the constructor.
    #
    # The background thread will be implicitly started the first time any of these methods is
    # called:
    #
    # - #active_zone?
    # - #on_active_zone
    # - #on_passive_zone
    #
    # or it can be explicitly started by calling #start_monitoring.
    #
    # Note: After a fork, the background thread will not be running; but it will be restarted
    # implicitly once any of the above methods are called.
    #
    # When monitoring is running, registered callbacks are invoked whenever an active zone change is
    # detected.
    #
    # == Basic usage
    #
    #   class CustomReplicationCoordinator < ActiveSupport::ReplicationCoordinator::Base
    #     def fetch_active_zone
    #       # Custom logic to determine if the local zone is active
    #     end
    #   end
    #
    #   coordinator = CustomReplicationCoordinator.new(polling_interval: 10.seconds)
    #
    #   coordinator.active_zone? # Immediately returns the cached value
    #
    #   coordinator.on_active_zone do |coordinator|
    #     puts "This zone is now active"
    #     # Start processes or threads that should only run in the active zone
    #   end
    #
    #   coordinator.on_passive_zone do |coordinator|
    #     puts "This zone is now passive"
    #     # Stop processes or threads that should only run in the active zone
    #   end
    #
    #   # Start a background thread to monitor the active zone status and invoke the callbacks on changes
    #   coordinator.start_monitoring
    #
    #   coordinator.updated_at # Returns the last time the active zone status was checked
    #
    # Subclasses must implement #fetch_active_zone
    class Base
      attr_reader :state_change_hooks, :polling_interval, :executor, :logger

      # Initialize a new coordinator instance.
      #
      # [+polling_interval+] How often to refresh active zone status (default: 5 seconds)
      def initialize(polling_interval: 5, executor: ActiveSupport::Executor, logger: nil)
        @polling_interval = polling_interval
        @executor = executor
        @logger = logger || (defined?(Rails.logger) && Rails.logger)
        @state_change_hooks = { active: [], passive: [] }

        @timer_task = nil
        @active_zone = nil
        @active_zone_updated_at = nil
        @lock = ActiveSupport::Concurrency::ShareLock.new
      end

      # Determine if the local zone is active.
      #
      # This method must be implemented by subclasses to define the logic for determining if the
      # local zone is active. The return value is used to trigger state change hooks when the active
      # zone changes.
      #
      # It's assumed that this method may be slow, so ReplicationCoordinator has a background thread
      # that calls this method every +polling_interval+ seconds, and caches the result which is
      # returned by #active_zone?
      #
      # Returns +true+ if the local zone is active, +false+ otherwise.
      def fetch_active_zone
        raise NotImplementedError
      end

      # Returns +true+ if the local zone is active, +false+ otherwise.
      # Also starts monitoring if it has not already been started.
      #
      # This always returns a cached value.
      def active_zone?
        start_monitoring
        @active_zone # No need to use a read lock
      end

      # Returns the time at which the current value of #active_zone? was fetched, or +nil+ if no
      # value has yet been fetched.
      #
      # This always returns a cached value.
      def updated_at
        @active_zone_updated_at # No need to use a read lock
      end

      # Start monitoring for active zone changes.
      #
      # This starts a Concurrent::TimerTask to periodically refresh the active zone status. If a
      # change is detected, then the appropriate state change callbacks will be invoked.
      def start_monitoring
        check_active_zone(skip_when_set: true)
        timer_task&.execute unless @timer_task&.running?
      end

      # Stop monitoring for active zone changes.
      #
      # This stops the Concurrent::TimerTask, if it is running.
      def stop_monitoring
        @timer_task&.shutdown
      end

      # Register a callback to be executed when the local zone becomes active.
      # Also starts monitoring if it has not already been started.
      #
      # The callback will be immediately executed if this zone is currently active.
      #
      # [+block+] callback to execute when zone becomes active
      #
      # Yields the coordinator instance to the block.
      def on_active_zone(&block)
        start_monitoring
        state_change_hooks[:active] << block
        block.call(self) if active_zone?
      end

      # Register a callback to be executed when the local zone becomes passive.
      # Also starts monitoring if it has not already been started.
      #
      # The callback will be immediately executed if this zone is not currently active.
      #
      # [+block+] callback to execute when zone becomes passive
      #
      # Yields the coordinator instance to the block.
      def on_passive_zone(&block)
        start_monitoring
        state_change_hooks[:passive] << block
        block.call(self) if !active_zone?
      end

      # Clear all registered state_change hooks.
      def clear_hooks
        state_change_hooks[:active] = []
        state_change_hooks[:passive] = []
      end

      private
        def check_active_zone(skip_when_set: false)
          return if skip_when_set && !@active_zone.nil?

          # Acquire an exclusive lock to mitigate a thundering herd problem when multiple threads
          # might all call active_zone? for the first time at the same time.
          if @lock.start_exclusive(no_wait: true)
            begin
              old_active_zone = @active_zone
              @active_zone = executor_wrap { fetch_active_zone }
              @active_zone_updated_at = Time.now
            ensure
              @lock.stop_exclusive
            end

            if old_active_zone.nil? || old_active_zone != @active_zone
              if @active_zone
                logger&.info "#{self.class}: pid #{$$}: switching to active"
                run_active_zone_hooks
              else
                logger&.info "#{self.class}: pid #{$$}: switching to passive"
                run_passive_zone_hooks
              end
            end
          else
            @lock.sharing { }
          end
        end

        def executor_wrap(&block)
          if @executor
            @executor.wrap(&block)
          else
            yield
          end
        end

        def run_active_zone_hooks
          run_hooks_for(:active)
        end

        def run_passive_zone_hooks
          run_hooks_for(:passive)
        end

        def run_hooks_for(event)
          state_change_hooks.fetch(event, []).each do |block|
            block.call(self)
          rescue Exception => exception
            handle_thread_error(exception)
          end
        end

        def timer_task
          @timer_task ||= begin
            task = Concurrent::TimerTask.new(execution_interval: polling_interval) do
              check_active_zone
            end

            task.add_observer do |_, _, error|
              if error
                executor.error_reporter&.report(error, handled: false, source: "replication_coordinator.active_support")
                logger&.error("#{error.detailed_message}: could not check #{self.class} active zone")
              end
            end

            # The thread-based timer task needs to be recreated after a fork.
            # FIXME: this callback is keeping a reference on the instance,
            # but only on active instances, and there should only be one of those.
            ActiveSupport::ForkTracker.after_fork { @timer_task = nil }

            task
          end
        end
    end

    # = "Single Zone" Replication Coordinator
    #
    # A concrete implementation that always indicates an active zone, and so it represents the
    # default behavior for a single-zone deployment that does not use database replication.
    #
    # This is a simple implementation that always returns +true+ from #active_zone?
    #
    # Note that this class does not use a background thread, since there is no need to monitor the
    # constant +true+ value.
    #
    # == Basic usage
    #
    #   rc = ActiveSupport::ReplicationCoordinator::SingleZone.new
    #   rc.active_zone? #=> true
    #   rc.on_active_zone { puts "Will always be called" }
    #   rc.on_passive_zone { puts "Will never be called" }
    class SingleZone < Base
      # Always returns true, indicating this zone is active.
      #
      # Returns true.
      def fetch_active_zone
        true
      end

      private
        def timer_task
          # No-op implementation since no monitoring is needed.
        end
    end
  end
end
