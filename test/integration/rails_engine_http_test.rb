# frozen_string_literal: true

require "json"
require "logger"
require "rack/mock"
require "action_controller/railtie"
require_relative "../test_helper"

module Step1510Fixtures
  class EchoHandler
    def self.call(message:, context:)
      text = message.fetch(:parts).filter_map { |part| part[:text] }.join("\n")
      "Echo: #{text}"
    end
  end

  class EchoAgent < A2A::Rails::Agent
    name "Echo Agent"
    description "Echo messages"
    version "1.0"

    skill :reply,
      description: "Echo a message",
      tags: %w[echo],
      handler: EchoHandler
  end
end

class RailsEngineHttpTest < Minitest::Test
  class TestApplication < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "step-15-10-secret-key-base"
    config.hosts.clear
    config.logger = Logger.new(nil)
  end

  TestApplication.initialize!

  def setup
    @original_configuration = A2A::Rails.instance_variable_get(:@configuration)
    @original_runtime = A2A::Rails.instance_variable_get(:@runtime)

    configuration = A2A::Rails::Configuration.new
    configuration.agent = "Step1510Fixtures::EchoAgent"
    configuration.logger = Logger.new(nil)
    A2A::Rails.instance_variable_set(:@configuration, configuration)
    A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new)
  end

  def teardown
    A2A::Rails.instance_variable_set(:@configuration, @original_configuration)
    A2A::Rails.instance_variable_set(:@runtime, @original_runtime)
  end

  def test_agent_card_is_exposed_without_explicit_host_route_mount
    response = request("GET", "/.well-known/agent-card.json")
    card = JSON.parse(response.body)

    assert_equal 200, response.status
    assert_equal "1.0", response["A2A-Version"]
    assert_equal "Echo Agent", card.fetch("name")
    assert_equal "reply", card.fetch("skills").first.fetch("id")
    assert_equal "http://example.org/a2a", card.fetch("supportedInterfaces").first.fetch("url")
  end

  def test_send_message_and_get_task_share_runtime_store_across_http_requests
    send_response = request(
      "POST",
      "/a2a",
      body: JSON.generate(
        "jsonrpc" => "2.0",
        "id" => "send-1",
        "method" => "SendMessage",
        "params" => {
          "message" => {
            "messageId" => "message-1",
            "role" => "ROLE_USER",
            "parts" => [{ "text" => "Hello" }]
          }
        }
      ),
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_A2A_VERSION" => "1.0"
      }
    )

    assert_equal 200, send_response.status
    assert_equal "1.0", send_response["a2a-version"]

    sent = JSON.parse(send_response.body)
    task = sent.fetch("result").fetch("task")
    assert_equal "TASK_STATE_COMPLETED", task.dig("status", "state")
    assert_equal "Echo: Hello", task.fetch("artifacts").first.fetch("parts").first.fetch("text")

    get_response = request(
      "POST",
      "/a2a",
      body: JSON.generate(
        "jsonrpc" => "2.0",
        "id" => "get-1",
        "method" => "GetTask",
        "params" => { "id" => task.fetch("id") }
      ),
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_A2A_VERSION" => "1.0"
      }
    )

    assert_equal 200, get_response.status
    fetched = JSON.parse(get_response.body).fetch("result")
    assert_equal task.fetch("id"), fetched.fetch("id")
    assert_equal "TASK_STATE_COMPLETED", fetched.dig("status", "state")
  end

  def test_explicit_public_base_url_overrides_request_base_url
    A2A::Rails.configuration.public_base_url = "https://agents.example.com/base/"

    response = request("GET", "/.well-known/agent-card.json")
    card = JSON.parse(response.body)

    assert_equal "https://agents.example.com/base/a2a", card.fetch("supportedInterfaces").first.fetch("url")
  end

  private

  def request(method, path, body: nil, headers: {})
    Rack::MockRequest.new(TestApplication.instance).request(
      method,
      path,
      headers.merge(input: body.to_s)
    )
  end
end
