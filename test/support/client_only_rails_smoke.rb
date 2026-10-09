# frozen_string_literal: true

# Separate-process Rails boot smoke: outbound-only applications must NOT
# register inbound Agent Card / JSON-RPC routes, even without config.agent.
require "logger"
require "rack/mock"
require "action_controller/railtie"
if ENV["A2A_RAILS_USE_INSTALLED_GEM"] == "1"
  require "a2a-rails"
  expected = ENV.fetch("A2A_RAILS_EXPECTED_VERSION")
  spec = Gem.loaded_specs.fetch("a2a-rails")
  source_root = ENV.fetch("A2A_RAILS_SOURCE_ROOT")
  raise "wrong installed Gem VERSION" unless A2A::Rails::VERSION == expected
  raise "Client-only boot used source checkout" if
    File.realpath(spec.full_gem_path).start_with?(File.realpath(source_root) + File::SEPARATOR)
  puts "Client-only Rails is loading installed Gem #{spec.full_gem_path}"
else
  require_relative "../../lib/a2a-rails"
end

module ClientOnlyRailsSmoke
  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "client-only-rails-smoke-secret"
    config.hosts.clear
    config.logger = Logger.new(nil)
    # Return a real 404 for an unmounted route instead of raising RoutingError.
    config.action_dispatch.show_exceptions = :all
  end

  module_function

  def check(condition, msg)
    raise msg unless condition
  end

  def run
    config = A2A::Rails::Configuration.new
    config.server_enabled = false
    config.validate!  # No Agent name is configured.
    A2A::Rails.instance_variable_set(:@configuration, config)

    Application.initialize!

    app = Rack::MockRequest.new(Application.instance)
    card = app.get("/.well-known/agent-card.json")
    rpc = app.post("/a2a",
      input: '{"jsonrpc":"2.0","id":"x","method":"GetTask","params":{"id":"task-1"}}',
      "CONTENT_TYPE" => "application/json")
    check(card.status == 404, "Client-only app exposed Agent Card: #{card.status}")
    check(rpc.status == 404, "Client-only app exposed A2A RPC: #{rpc.status}")

    client = A2A::Rails::Client.new(
      agent_card_url: "https://remote.example/.well-known/agent-card.json",
      allowed_origins: ["https://remote.example"]
    )
    check(client.is_a?(A2A::Rails::Client), "Outbound Client unavailable without Server")
    check(config.agent.nil?, "Client-only app unexpectedly requires Server Agent")
    check(!A2A::Rails.instance_variable_defined?(:@runtime),
      "Client-only initialization unexpectedly constructed inbound Runtime")

    puts "Step 29-4b client-only Rails smoke: PASS"
  end
end

ClientOnlyRailsSmoke.run
