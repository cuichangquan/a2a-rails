# frozen_string_literal: true

require "json"
require "logger"
require "rack/mock"
require "action_controller/railtie"
require_relative "../../lib/a2a-rails"

module Step1510Smoke
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

  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "step-15-10-secret-key-base"
    config.hosts.clear
    config.logger = Logger.new(nil)
    config.action_dispatch.show_exceptions = :none
  end

  module_function

  def assert(condition, message)
    raise message unless condition
  end

  def request(method, path, body: nil, headers: {})
    Rack::MockRequest.new(Application.instance).request(
      method,
      path,
      headers.merge(input: body.to_s)
    )
  end

  def run
    configuration = A2A::Rails::Configuration.new
    configuration.agent = "Step1510Smoke::EchoAgent"
    configuration.logger = Logger.new(nil)
    A2A::Rails.instance_variable_set(:@configuration, configuration)
    A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new)

    Application.initialize!

    card_response = request("GET", "/.well-known/agent-card.json")
    assert(card_response.status == 200, "Agent Card status: #{card_response.status} #{card_response.body}")
    card = JSON.parse(card_response.body)
    assert(card_response["A2A-Version"] == "1.0", "Agent Card A2A-Version header missing")
    assert(card.fetch("name") == "Echo Agent", "unexpected Agent Card name")
    assert(card.fetch("skills").first.fetch("id") == "reply", "unexpected Agent Card Skill")
    assert(card.fetch("supportedInterfaces").first.fetch("url") == "http://example.org/a2a", "unexpected request-derived A2A URL")

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
    assert(send_response.status == 200, "SendMessage status: #{send_response.status} #{send_response.body}")
    assert(send_response["a2a-version"] == "1.0", "SendMessage A2A-Version header missing")

    sent = JSON.parse(send_response.body)
    task = sent.fetch("result").fetch("task")
    assert(task.dig("status", "state") == "TASK_STATE_COMPLETED", "SendMessage did not complete")
    assert(task.fetch("artifacts").first.fetch("parts").first.fetch("text") == "Echo: Hello", "unexpected Artifact text")

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
    assert(get_response.status == 200, "GetTask status: #{get_response.status} #{get_response.body}")
    fetched = JSON.parse(get_response.body).fetch("result")
    assert(fetched.fetch("id") == task.fetch("id"), "Runtime Task Store was not shared across requests")
    assert(fetched.dig("status", "state") == "TASK_STATE_COMPLETED", "GetTask returned wrong state")

    configuration.public_base_url = "https://agents.example.com/base/"
    explicit_card_response = request("GET", "/.well-known/agent-card.json")
    assert(explicit_card_response.status == 200, "explicit Agent Card status: #{explicit_card_response.status} #{explicit_card_response.body}")
    explicit_card = JSON.parse(explicit_card_response.body)
    assert(
      explicit_card.fetch("supportedInterfaces").first.fetch("url") == "https://agents.example.com/base/a2a",
      "explicit public_base_url did not override request base URL"
    )

    # Step 16-2: the host application verifies credentials before the SDK
    # sees the request; a denied call must not execute a Handler.
    configuration.authentication_challenge = 'Bearer realm="echo-agent"'
    configuration.authenticate_request = lambda do |rails_request|
      authorization = rails_request.get_header("HTTP_AUTHORIZATION")
      raise A2A::Rails::Authentication::Forbidden if authorization == "Bearer forbidden-token"

      "verified-client-1" if authorization == "Bearer valid-token"
    end

    auth_payload = JSON.generate(
      "jsonrpc" => "2.0",
      "id" => "auth-1",
      "method" => "SendMessage",
      "params" => {
        "message" => {
          "messageId" => "auth-message-1",
          "role" => "ROLE_USER",
          "parts" => [{ "text" => "Authenticated" }]
        }
      }
    )
    auth_headers = { "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0" }

    denied = request("POST", "/a2a", body: auth_payload, headers: auth_headers)
    assert(denied.status == 401, "unauthenticated request was not denied: #{'#{denied.status}'}")
    assert(denied["WWW-Authenticate"] == 'Bearer realm="echo-agent"', "missing authentication challenge")
    assert(JSON.parse(denied.body).fetch("error") == "Unauthorized", "unsafe authentication response")
    assert(denied["Cache-Control"].to_s.include?("no-store"), "authentication response can be cached")

    invalid = request("POST", "/a2a", body: auth_payload,
      headers: auth_headers.merge("HTTP_AUTHORIZATION" => "Bearer wrong-token"))
    assert(invalid.status == 401, "invalid token was not denied")

    forbidden = request("POST", "/a2a", body: auth_payload,
      headers: auth_headers.merge("HTTP_AUTHORIZATION" => "Bearer forbidden-token"))
    assert(forbidden.status == 403, "explicit forbidden request was not denied")
    assert(JSON.parse(forbidden.body).fetch("error") == "Forbidden", "unsafe forbidden response")

    allowed = request("POST", "/a2a", body: auth_payload,
      headers: auth_headers.merge("HTTP_AUTHORIZATION" => "Bearer valid-token"))
    assert(allowed.status == 200, "authenticated request failed: #{'#{allowed.status}'}")
    assert(JSON.parse(allowed.body).dig("result", "task", "artifacts", 0, "parts", 0, "text") ==
      "Echo: Authenticated", "authenticated Handler did not run")

    configuration.authenticate_request = ->(_request) { raise "secret-token-shall-not-appear" }
    unavailable = request("POST", "/a2a", body: auth_payload, headers: auth_headers)
    assert(unavailable.status == 500, "verifier failure was not safely handled")
    assert(JSON.parse(unavailable.body).fetch("error") == "Authentication unavailable", "unsafe error")
    assert(!unavailable.body.include?("secret-token-shall-not-appear"), "verifier secret leaked")

    puts "Step 15-10 Rails HTTP smoke: PASS"
  end
end

Step1510Smoke.run
