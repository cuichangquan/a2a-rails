# frozen_string_literal: true

# Separate-process Rails boot smoke: outbound-only applications must NOT
# register inbound Agent Card / JSON-RPC routes, even without config.agent.
require "logger"
require "rack/mock"
require "action_controller/railtie"
require_relative "../../lib/a2a-rails"

module ClientOnlyRailsSmoke
  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "client-only-rails-smoke-secret"
    config.hosts.clear
    config.logger = Logger.new(nil)
    config.action_dispatch.show_exceptions = :none
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
