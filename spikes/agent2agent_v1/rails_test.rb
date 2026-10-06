# frozen_string_literal: true

require "minitest/autorun"
require "rails"
require "action_controller/railtie"
require "rack/mock"
require_relative "app"

class SpikeRailsApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "a" * 64
  config.hosts.clear
  config.logger = Logger.new($stdout)
end

SpikeRailsApplication.initialize!
probe = Agent2AgentV1Spike::App.new
# Exact Rails routes do not expose the SDK's internal transport paths.
SpikeRailsApplication.routes.draw do
  get "/.well-known/agent-card.json", to: probe
  post "/a2a", to: probe
end

class Agent2AgentRailsSpikeTest < Minitest::Test
  def test_rails_routes_use_real_sdk
    rack = Rack::MockRequest.new(SpikeRailsApplication)
    card_response = rack.get("/.well-known/agent-card.json")
    assert_equal 200, card_response.status
    assert_equal "1.0", JSON.parse(card_response.body).dig("supportedInterfaces", 0, "protocolVersion")
    response = rack.post("/a2a", "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(jsonrpc: "2.0", id: 7, method: "SendMessage", params: {
        message: { messageId: "rails-message", role: "ROLE_USER", parts: [{ text: "Hello" }] }
      }))
    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal 7, body["id"]
    assert_equal "TASK_STATE_COMPLETED", body.dig("result", "task", "status", "state")
    assert_equal "Echo: Hello", body.dig("result", "task", "artifacts", 0, "parts", 0, "text")
    %w[/a2a/rest /a2a/grpc /a2a/.well-known/agent-card.json].each do |path|
      assert_equal 404, rack.get(path).status
    end
  end
end
