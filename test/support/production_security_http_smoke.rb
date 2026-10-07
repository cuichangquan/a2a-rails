# frozen_string_literal: true

# Run in a separate process with RAILS_ENV=production. This proves that the
# production fail-closed behavior is not a dev/test-only stub.
require "json"
require "logger"
require "rack/mock"
require "action_controller/railtie"
require_relative "../../lib/a2a-rails"

module Step166ProductionSecuritySmoke
  class EchoHandler
    class << self
      attr_accessor :calls
    end
    self.calls = 0

    def self.call(message:, context:)
      self.calls += 1
      "Echo: #{message.dig(:parts, 0, :text)}"
    end
  end

  class EchoAgent < A2A::Rails::Agent
    name "Production Security Test Agent"
    description "Security test only"
    version "1.0"
    skill :reply,
      description: "Reply to a message",
      tags: %w[test],
      handler: EchoHandler
  end

  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "step-16-6-production-security-sample-only"
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
      method, path, headers.merge(input: body.to_s)
    )
  end

  def rpc(token, method, params)
    request(
      "POST", "/a2a",
      body: JSON.generate("jsonrpc" => "2.0", "id" => "prod-smoke", "method" => method, "params" => params),
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_A2A_VERSION" => "1.0",
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      }
    )
  end

  def send_params(text)
    {
      "message" => {
        "messageId" => "production-smoke-msg-#{text}",
        "role" => "ROLE_USER",
        "parts" => [{ "text" => text }]
      }
    }
  end

  def run
    assert(::Rails.env.production?, "must run with RAILS_ENV=production")

    configuration = A2A::Rails::Configuration.new
    configuration.agent = "Step166ProductionSecuritySmoke::EchoAgent"
    configuration.public_base_url = "https://agents.example.test"
    configuration.logger = Logger.new(nil)
    A2A::Rails.instance_variable_set(:@configuration, configuration)
    A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new)
    Application.initialize!

    absent_card = request("GET", "/.well-known/agent-card.json")
    assert(absent_card.status == 503, "unconfigured production Agent Card must not imply anonymous access")
    assert(JSON.parse(absent_card.body).fetch("error") == "Agent Card unavailable", "unsafe card error")

    missing_config = rpc("present-but-unverified", "SendMessage", send_params("blocked"))
    assert(missing_config.status == 401, "production POST must fail closed without authenticator")
    assert(missing_config["WWW-Authenticate"] == 'Bearer realm="a2a"', "missing Bearer challenge")
    assert(EchoHandler.calls.zero?, "production request reached Handler without auth")

    # Configure both the actual host verifier and the corresponding public
    # Agent Card. This is a test verifier, NOT a real token validation example.
    configuration.security_schemes = {
      "bearer" => { "httpAuthSecurityScheme" => { "scheme" => "Bearer" } }
    }
    configuration.security_requirements = [
      { "schemes" => { "bearer" => { "list" => [] } } }
    ]
    configuration.authenticate_request = lambda do |req|
      auth = req.get_header("HTTP_AUTHORIZATION")
      raise A2A::Rails::Authentication::Forbidden if auth == "Bearer forbidden"
      case auth
      when "Bearer client-a" then "tenant-A:client"
      when "Bearer client-b" then "tenant-B:client"
      end
    end

    card = request("GET", "/.well-known/agent-card.json")
    assert(card.status == 200, "secured Agent Card must be discoverable")
    card_data = JSON.parse(card.body)
    assert(card_data.dig("securitySchemes", "bearer", "httpAuthSecurityScheme", "scheme") == "Bearer",
      "secured Agent Card missing Bearer security scheme")
    assert(card_data.fetch("securityRequirements") ==
      [{ "schemes" => { "bearer" => { "list" => [] } } }],
      "card security does not match verifier")
    assert(card_data.fetch("supportedInterfaces").first.fetch("url") ==
      "https://agents.example.test/a2a", "public card did not use configured HTTPS URL")

    ["", "bogus"].each do |token|
      rejected = rpc(token, "SendMessage", send_params("blocked"))
      assert(rejected.status == 401, "invalid or missing Bearer token must be rejected")
    end
    forbidden = rpc("forbidden", "SendMessage", send_params("blocked"))
    assert(forbidden.status == 403, "host policy denial should be forbidden")
    assert(EchoHandler.calls.zero?, "unauthorized Handler invoked")

    a = rpc("client-a", "SendMessage", send_params("hello"))
    assert(a.status == 200, "valid client-a request did not succeed: #{a.status}")
    task_id = JSON.parse(a.body).dig("result", "task", "id")
    assert(task_id.is_a?(String) && !task_id.empty?, "no Task returned for authorized request")
    assert(EchoHandler.calls == 1, "valid Handler was not invoked exactly once")

    own = rpc("client-a", "GetTask", "id" => task_id)
    assert(own.status == 200 && JSON.parse(own.body).dig("result", "id") == task_id,
      "own Task access was denied")
    foreign = rpc("client-b", "GetTask", "id" => task_id)
    assert(foreign.status == 200 &&
      JSON.parse(foreign.body).dig("error", "code") == -32_001, "foreign Task access was allowed")
    listing = rpc("client-b", "ListTasks", {})
    assert(JSON.parse(listing.body).dig("result", "totalSize") == 0, "foreign Task was listed")
    assert(!card.body.include?("tenant-A:client"), "card leaked an internal verified principal")

    configuration.max_request_bytes = 20
    oversized = rpc("client-a", "SendMessage", send_params("oversized"))
    assert(oversized.status == 413, "production payload-size limit was not enforced")
    assert(EchoHandler.calls == 1, "oversized body reached Handler")

    configuration.max_request_bytes = A2A::Rails::RequestGuard::DEFAULT_MAX_BYTES
    configuration.security_requirements = nil
    inconsistent = request("GET", "/.well-known/agent-card.json")
    assert(inconsistent.status == 503, "inconsistent production card did not fail closed")
    invalid = rpc("client-a", "SendMessage", send_params("misconfigured"))
    assert(invalid.status == 500, "mismatched verifier and card metadata did not fail closed")
    assert(EchoHandler.calls == 1, "inconsistent security configuration reached Handler")

    puts "Step 16-6 production HTTP security smoke: PASS"
  end
end

Step166ProductionSecuritySmoke.run
