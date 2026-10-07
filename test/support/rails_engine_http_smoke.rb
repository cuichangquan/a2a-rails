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

      case authorization
      when "Bearer valid-token" then "verified-client-1"
      when "Bearer second-token" then "verified-client-2"
      end
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
    assert(denied.status == 401, "unauthenticated request was not denied: #{denied.status}")
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
    assert(allowed.status == 200, "authenticated request failed: #{allowed.status}")
    assert(JSON.parse(allowed.body).dig("result", "task", "artifacts", 0, "parts", 0, "text") ==
      "Echo: Authenticated", "authenticated Handler did not run")

    # Step 16-3: authenticated callers share an HTTP endpoint and a Task Store,
    # but may not read, enumerate, continue, or cancel each other's Tasks.
    scoped_rpc = lambda do |token, method, params|
      response = request(
        "POST", "/a2a",
        body: JSON.generate("jsonrpc" => "2.0", "id" => "scope-1", "method" => method, "params" => params),
        headers: auth_headers.merge("HTTP_AUTHORIZATION" => "Bearer #{token}")
      )
      assert(response.status == 200, "scoped RPC #{method} failed HTTP #{response.status}")
      JSON.parse(response.body)
    end

    send_params = lambda do |text, id|
      {
        "message" => {
          "messageId" => id,
          "role" => "ROLE_USER",
          "contextId" => "shared-context",
          "parts" => [{ "text" => text }]
        }
      }
    end

    a1 = scoped_rpc.call("valid-token", "SendMessage", send_params.call("A-1", "a1")).dig("result", "task")
    a2 = scoped_rpc.call("valid-token", "SendMessage", send_params.call("A-2", "a2")).dig("result", "task")
    b1 = scoped_rpc.call("second-token", "SendMessage", send_params.call("B-1", "b1")).dig("result", "task")
    assert(a1.fetch("id") != b1.fetch("id"), "different callers received same task ID")
    assert(!JSON.generate(a1).include?("verified-client-1"), "Task wire output leaked owner")

    assert(scoped_rpc.call("valid-token", "GetTask", "id" => a1.fetch("id")).dig("result", "id") ==
      a1.fetch("id"), "owner could not fetch Task")
    assert(scoped_rpc.call("second-token", "GetTask", "id" => a1.fetch("id")).dig("error", "code") ==
      -32_001, "foreign Task was readable")
    assert(scoped_rpc.call("valid-token", "GetTask", "id" => b1.fetch("id")).dig("error", "code") ==
      -32_001, "reverse Task ownership check failed")

    alice_list = scoped_rpc.call("valid-token", "ListTasks",
      "contextId" => "shared-context", "pageSize" => 1).fetch("result")
    assert(alice_list.fetch("totalSize") == 2, "ListTasks leaked foreign Task in totalSize")
    assert(!alice_list.fetch("nextPageToken").empty?, "expected an owner-specific page token")
    alice_next = scoped_rpc.call("valid-token", "ListTasks",
      "contextId" => "shared-context", "pageSize" => 1,
      "pageToken" => alice_list.fetch("nextPageToken")).fetch("result")
    assert((alice_list.fetch("tasks") + alice_next.fetch("tasks")).map { |row| row.fetch("id") }.sort ==
      [a1.fetch("id"), a2.fetch("id")].sort, "owner's ListTasks pagination was incomplete")

    bob_list = scoped_rpc.call("second-token", "ListTasks",
      "contextId" => "shared-context").fetch("result")
    assert(bob_list.fetch("totalSize") == 1, "Bob saw Alice's Tasks")
    assert(bob_list.fetch("tasks").map { |row| row.fetch("id") } == [b1.fetch("id")],
      "cross-owner Task enumeration")

    stolen_cursor = scoped_rpc.call("second-token", "ListTasks",
      "contextId" => "shared-context", "pageSize" => 1,
      "pageToken" => alice_list.fetch("nextPageToken"))
    assert(stolen_cursor.dig("error", "code") == -32_602, "page token was not bound to owner")

    foreign_continuation = send_params.call("continue", "continue-1")
    foreign_continuation.fetch("message")["taskId"] = a1.fetch("id")
    assert(scoped_rpc.call("second-token", "SendMessage", foreign_continuation).dig("error", "code") ==
      -32_001, "foreign Task existence leaked via continuation")
    assert(scoped_rpc.call("valid-token", "SendMessage", foreign_continuation).dig("error", "code") ==
      -32_004, "own Task continuation did not retain unsupported-operation error")

    # Canceling a Task is atomic and the non-owner must see not-found.
    store = A2A::Rails.runtime.instance_variable_get(:@store)
    lifecycle = A2A::Rails::Task::Lifecycle.new(store: store, principal_id: "verified-client-1")
    pending = lifecycle.create(message: {
      message_id: "pending-1", role: :user,
      parts: [{ text: "Hold", media_type: "text/plain" }], metadata: {}
    })
    lifecycle.start(pending.fetch(:id))
    assert(scoped_rpc.call("second-token", "CancelTask", "id" => pending.fetch(:id)).dig("error", "code") ==
      -32_001, "foreign Task cancellation was allowed")
    assert(scoped_rpc.call("valid-token", "CancelTask", "id" => pending.fetch(:id)).dig("result", "status", "state") ==
      "TASK_STATE_CANCELED", "owner could not cancel Task")

    # Step 16-4: HTTP payload limits and media type validation run before
    # the verifier or protocol SDK reads the JSON-RPC request.
    configuration.max_request_bytes = 256
    big_request = request(
      "POST", "/a2a",
      body: auth_payload + (" " * 1024),
      headers: auth_headers.merge("HTTP_AUTHORIZATION" => "Bearer valid-token")
    )
    assert(big_request.status == 413, "oversized A2A request was not rejected")
    assert(JSON.parse(big_request.body).fetch("error") == "Payload too large",
      "oversized request returned unsafe error")
    assert(big_request["Cache-Control"].to_s.include?("no-store"),
      "oversized A2A response can be cached")

    configuration.max_request_bytes = A2A::Rails::RequestGuard::DEFAULT_MAX_BYTES
    wrong_type = request(
      "POST", "/a2a",
      body: auth_payload,
      headers: auth_headers.merge(
        "HTTP_AUTHORIZATION" => "Bearer valid-token",
        "CONTENT_TYPE" => "text/plain"
      )
    )
    assert(wrong_type.status == 415, "non-JSON request was not rejected")

    compressed = request(
      "POST", "/a2a",
      body: auth_payload,
      headers: auth_headers.merge(
        "HTTP_AUTHORIZATION" => "Bearer valid-token",
        "HTTP_CONTENT_ENCODING" => "gzip"
      )
    )
    assert(compressed.status == 415, "compressed input was not rejected")

    configuration.max_request_bytes = 0
    invalid_limit = request(
      "POST", "/a2a",
      body: auth_payload,
      headers: auth_headers.merge("HTTP_AUTHORIZATION" => "Bearer valid-token")
    )
    assert(invalid_limit.status == 500, "invalid request guard configuration was not rejected")
    assert(JSON.parse(invalid_limit.body).fetch("error") == "Request validation unavailable",
      "invalid config leaked exception details")
    configuration.max_request_bytes = A2A::Rails::RequestGuard::DEFAULT_MAX_BYTES

    configuration.authenticate_request = ->(_request) { raise "secret-token-shall-not-appear" }
    unavailable = request("POST", "/a2a", body: auth_payload, headers: auth_headers)
    assert(unavailable.status == 500, "verifier failure was not safely handled")
    assert(JSON.parse(unavailable.body).fetch("error") == "Authentication unavailable", "unsafe error")
    assert(!unavailable.body.include?("secret-token-shall-not-appear"), "verifier secret leaked")

    puts "Step 15-10 Rails HTTP smoke: PASS"
  end
end

Step1510Smoke.run
