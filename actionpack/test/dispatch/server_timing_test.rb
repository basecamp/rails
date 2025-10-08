# frozen_string_literal: true

require "abstract_unit"

class ServerTimingTest < ActionDispatch::IntegrationTest
  class TestController < ActionController::Base
    def index
      head :ok
    end

    def show
      ActiveSupport::Notifications.instrument("custom.event") do
        true
      end
      head :ok
    end

    def create
      ActiveSupport::Notifications.instrument("custom.event") do
        raise
      end
    end
  end

  setup do
    @middlewares = [Rack::Lint, ActionDispatch::ServerTiming, Rack::Lint]
    @header_name = ActionDispatch::Constants::SERVER_TIMING
  end

  teardown do
    # Avoid leaking subscription into other tests
    # This will break any active instance of the middleware, but we don't
    # expect there to be any outside of this file.
    ActionDispatch::ServerTiming.unsubscribe
  end

  test "server timing header is included in the response" do
    with_test_route_set do
      get "/"
      assert_match(/\w+/, @response.headers[@header_name])
    end
  end

  test "includes default action controller events duration" do
    with_test_route_set do
      get "/"
      assert_match(/start_processing.action_controller;dur=\w+/, @response.headers[@header_name])
      assert_match(/process_action.action_controller;dur=\w+/, @response.headers[@header_name])
    end
  end

  test "includes custom active support events duration" do
    with_test_route_set do
      get "/id"
      assert_match(/custom.event;dur=\w+/, @response.headers[@header_name])
    end
  end

  test "events are tracked by thread" do
    barrier = Concurrent::CyclicBarrier.new(2)

    stub_app = -> (env) {
      env["action_dispatch.test"].call
      [200, {}, "ok"]
    }
    app = Rack::Lint.new(
      ActionDispatch::ServerTiming.new(Rack::Lint.new(stub_app))
    )

    t1 = Thread.new do
      proc = -> {
        barrier.wait
        barrier.wait
      }
      env = Rack::MockRequest.env_for("", { "action_dispatch.test" => proc })
      app.call(env)
    end

    t2 = Thread.new do
      barrier.wait
      proc = -> {
        ActiveSupport::Notifications.instrument("custom.event") do
          true
        end
      }
      env = Rack::MockRequest.env_for("", { "action_dispatch.test" => proc })
      response = app.call(env)

      barrier.wait

      response
    end

    headers1 = t1.value[1]
    headers2 = t2.value[1]

    assert_match(/custom.event;dur=\w+/, headers2[@header_name])
    assert_no_match(/custom.event;dur=\w+/, headers1[@header_name])
  end

  test "does not overwrite existing header values" do
    @middlewares << Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        header_name = ActionDispatch::Constants::SERVER_TIMING
        headers[header_name] = [headers[header_name], %(entry;desc="description")].compact.join(", ")
        [ status, headers, body ]
      end
    end

    with_test_route_set do
      get "/"
      assert_match(/entry;desc="description"/, @response.headers[@header_name])
      assert_match(/start_processing.action_controller;dur=\w+/, @response.headers[@header_name])
    end
  end

  test "runtime_only mode converts X-Runtime to Server-Timing header" do
    # Simulate Rack::Runtime setting the X-Runtime header
    app = Rack::Lint.new(
      ActionDispatch::ServerTiming.new(
        Rack::Lint.new(->(_env) { [200, { "x-runtime" => "0.123456" }, ["ok"]] }),
        :runtime_only
      )
    )

    env = Rack::MockRequest.env_for("/")
    status, headers, body = app.call(env)

    assert_equal 200, status
    # X-Runtime is in seconds, Server-Timing should be in milliseconds
    assert_equal "total;dur=123.46", headers[@header_name]
  end

  test "runtime_only mode does nothing if X-Runtime header is missing" do
    app = Rack::Lint.new(
      ActionDispatch::ServerTiming.new(
        Rack::Lint.new(->(_env) { [200, {}, ["ok"]] }),
        :runtime_only
      )
    )

    env = Rack::MockRequest.env_for("/")
    status, headers, body = app.call(env)

    assert_equal 200, status
    assert_nil headers[@header_name]
  end

  test "runtime_only mode appends to existing Server-Timing header" do
    app = Rack::Lint.new(
      ActionDispatch::ServerTiming.new(
        Rack::Lint.new(->(_env) {
          [200, {
            ActionDispatch::Constants::SERVER_TIMING => "custom;dur=100",
            "x-runtime" => "0.05"
          }, ["ok"]]
        }),
        :runtime_only
      )
    )

    env = Rack::MockRequest.env_for("/")
    status, headers, body = app.call(env)

    assert_equal 200, status
    assert_equal "custom;dur=100, total;dur=50.00", headers[@header_name]
  end

  test "runtime_only mode does not subscribe to notifications" do
    # Create middleware with runtime_only mode
    middleware = ActionDispatch::ServerTiming.new(
      ->(_env) { [200, {}, ["ok"]] },
      :runtime_only
    )

    # Ensure subscriber is not initialized in runtime_only mode
    assert_nil middleware.instance_variable_get(:@subscriber)
  end

  private
    def app
      @app ||= self.class.build_app do |middleware|
        @middlewares.each { |m| middleware.use m }
      end
    end

    def with_test_route_set
      with_routing do |set|
        set.draw do
          get "/", to: ::ServerTimingTest::TestController.action(:index)
          get "/id", to: ::ServerTimingTest::TestController.action(:show)
          post "/", to: ::ServerTimingTest::TestController.action(:create)
        end

        yield
      end
    end
end
