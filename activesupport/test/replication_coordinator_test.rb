# frozen_string_literal: true

require "active_support/replication_coordinator"
require "active_support/testing/replication_coordinator"
require "active_support/error_reporter/test_helper"

class ReplicationCoordinatorTest < ActiveSupport::TestCase
  test "polling_interval can be set and has a good default" do
    klass = Class.new(ActiveSupport::ReplicationCoordinator::Base) do
      def fetch_active_zone
        true
      end
    end

    assert_equal 5, klass.new.polling_interval
    assert_equal 1, klass.new(polling_interval: 1).polling_interval
  end

  test "fetch_active_zone is cached" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(polling_interval: 9999)
    rc.start_monitoring

    10.times { rc.active_zone? }
    10.times { rc.on_active_zone { } }
    10.times { rc.on_passive_zone { } }

    assert_equal 1, rc.fetch_count
  end

  test "updated_at is set whenever monitoring calls fetch_active_zone" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true, polling_interval: 0.01)
    rc.active_zone?
    original_time = rc.updated_at

    rc.start_monitoring
    Timeout.timeout(0.1) { sleep 0.01 while rc.fetch_count < 2 }
    rc.stop_monitoring

    assert rc.updated_at > original_time
  end

  test "the initial fetch is guarded against a thundering herd" do
    rc = Class.new(ActiveSupport::ReplicationCoordinator::Base) do
      attr_reader :fetch_count

      def initialize(...)
        @fetch_count = 0
        super
      end

      def fetch_active_zone
        @fetch_count += 1
        sleep 0.1
        true
      end
    end.new

    10.times.map { Thread.new { rc.active_zone? } }.map(&:join)

    assert_equal 1, rc.fetch_count
  end

  test "the initial active_zone? fetches once" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true)
    assert_equal 0, rc.fetch_count
    assert_nil rc.updated_at

    freeze_time do
      rc.active_zone?
      assert_equal 1, rc.fetch_count
      assert_equal Time.now, rc.updated_at
    end
  end

  test "active_zone? starts monitoring" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true, polling_interval: 0.01)

    rc.active_zone?

    Timeout.timeout(0.1) { sleep 0.01 while rc.fetch_count < 3 }
    assert rc.fetch_count >= 3
  end

  test "the initial on_active_zone fetches once" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true)
    assert_equal 0, rc.fetch_count
    assert_nil rc.updated_at

    freeze_time do
      rc.on_active_zone { }
      assert_equal 1, rc.fetch_count
      assert_equal Time.now, rc.updated_at
    end
  end

  test "on_active_zone hooks are called once, immediately upon registration" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true)
    active_cb_count = passive_cb_count = 0

    rc.on_active_zone { active_cb_count += 1 }
    rc.on_passive_zone { passive_cb_count += 1 }

    assert_equal 1, active_cb_count
    assert_equal 0, passive_cb_count
  end

  test "on_active_zone starts monitoring" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true, polling_interval: 0.01)

    rc.on_active_zone { }

    Timeout.timeout(0.1) { sleep 0.01 while rc.fetch_count < 3 }
    assert rc.fetch_count >= 3
  end

  test "the initial on_passive_zone fetches once" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(true)
    assert_equal 0, rc.fetch_count
    assert_nil rc.updated_at

    freeze_time do
      rc.on_passive_zone { }
      assert_equal 1, rc.fetch_count
      assert_equal Time.now, rc.updated_at
    end
  end

  test "on_passive_zone hooks are called once, immediately upon registration" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(false)
    active_cb_count = passive_cb_count = 0

    rc.on_passive_zone { passive_cb_count += 1 }
    rc.on_active_zone { active_cb_count += 1 }

    assert_equal 0, active_cb_count
    assert_equal 1, passive_cb_count
  end

  test "on_passive_zone starts monitoring" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(false, polling_interval: 0.01)

    rc.on_passive_zone { }

    Timeout.timeout(0.1) { sleep 0.01 while rc.fetch_count < 3 }
    assert rc.fetch_count >= 3
  end

  test "hooks are called upon transition while monitoring" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(false, polling_interval: 0.01)
    active_cb_count = passive_cb_count = 0
    rc.on_active_zone { active_cb_count += 1 }
    rc.on_passive_zone { passive_cb_count += 1 }

    active_cb_count = passive_cb_count = 0
    rc.set_next_active_zone(true)

    Timeout.timeout(0.1) { sleep 0.01 while active_cb_count == 0 }

    assert_equal 1, active_cb_count
    assert_equal 0, passive_cb_count

    active_cb_count = passive_cb_count = 0
    rc.set_next_active_zone(false)

    Timeout.timeout(0.1) { sleep 0.01 while passive_cb_count == 0 }

    assert_equal 0, active_cb_count
    assert_equal 1, passive_cb_count
  ensure
    rc&.stop_monitoring
  end

  test "errors are logged when raised calling fetch_active_zone from the timer task" do
    klass = Class.new(ActiveSupport::ReplicationCoordinator::Base) do
      attr_reader :fetch_count

      def initialize(...)
        @fetch_count = 0
        super
      end

      def fetch_active_zone
        @fetch_count += 1
        raise "Simulated exception resolving active zone" if @fetch_count == 3
        true
      end
    end

    rc = klass.new(polling_interval: 0.01)

    subscriber = ActiveSupport::ErrorReporter::TestHelper::ErrorSubscriber.new
    ActiveSupport.error_reporter.subscribe(subscriber)

    rc.start_monitoring
    Timeout.timeout(0.1) { sleep 0.01 while rc.fetch_count < 6 }

    assert rc.fetch_count >= 6 # the timer task continues running after an error

    assert_equal 1, subscriber.events.count
    assert_equal "Simulated exception resolving active zone", subscriber.events[0][0].message
  ensure
    rc&.stop_monitoring
  end

  test "monitoring will be organically restarted after forking" do
    rc = ActiveSupport::Testing::ReplicationCoordinator.new(polling_interval: 0.01)
    rc.active_zone?

    out, _ = capture_subprocess_io do
      child = Process.fork do
        initial_fetch_count = rc.fetch_count
        rc.active_zone?

        begin
          Timeout.timeout(0.1) { sleep 0.01 while rc.fetch_count < initial_fetch_count + 5 }
          puts "OK"
        rescue Timeout::Error
          puts "FAIL"
        end
      end
      Process.wait child
    end

    assert_equal "OK", out.chomp
  end

  test "SingleZone can be used for the default always-active behavior" do
    rc = ActiveSupport::ReplicationCoordinator::SingleZone.new
    assert rc.active_zone?
    assert_nil rc.instance_variable_get(:@timer_task) # No timer task is created for SingleZone
  end
end
