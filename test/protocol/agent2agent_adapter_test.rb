# frozen_string_literal: true

require "json"
require "rack/mock"
require_relative "../test_helper"

class Agent2AgentAdapterTest < Minitest::Test
  AGENT_CARD = {
    "name" => "Adapter Test Agent",
    "description" => "a2a-rails protocol adapter test",
    "version" => "0.1.0",
    "supportedInterfaces" => [
      { "url" => "http://example.test/a2a", "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" }
    ],
    "capabilities" => { "streaming" => false, "pushNotifications" => false, "extendedAgentCard" => false },
    "defaultInputModes" => ["text/plain"],
    "defaultOutputModes" => ["text/plain"],
    "skills" => [
      { "id" => "reply", "name" => "Reply", "description" => "Reply to a message", "tags" => ["test"] }
    ]
  }.freeze

  class ReadOnlyInput
    def initialize(body)
      @body = body
    end

    def read
      @body
    end
  end

  def test_abstract_adapter_requires_call_implementation
    error = assert_raises(NotImplementedError) { A2A::Rails::Protocol::Adapter.new.call({}) }
    assert_match(/implement #call/, error.message)
  end

  def test_real_sdk_request_is_hidden_behind_plain_hash_boundary
    seen = nil
    handler = lambda do |operation:, params:|
      seen = [operation, params]
      { "tasks" => [], "totalSize" => 0, "pageSize" => 50, "nextPageToken" => "" }
    end
    adapter = build_adapter(handler)

    response = Rack::MockRequest.new(adapter).post(
      "/a2a",
      "CONTENT_TYPE" => "application/json",
      "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(jsonrpc: "2.0", id: "adapter-1", method: "ListTasks", params: {})
    )

    assert_equal 200, response.status
    assert_equal "1.0", response["a2a-version"]
    assert_equal "adapter-1", JSON.parse(response.body)["id"]
    assert_equal "ListTasks", seen[0]
    assert_kind_of Hash, seen[1]
  end

  def test_missing_version_is_rejected_and_query_version_is_accepted
    adapter = build_adapter(lambda do |operation:, params:|
      { "tasks" => [], "totalSize" => 0, "pageSize" => 50, "nextPageToken" => "" }
    end)
    rack = Rack::MockRequest.new(adapter)
    payload = JSON.generate(jsonrpc: "2.0", id: 1, method: "ListTasks", params: {})

    missing = rack.post("/a2a", "CONTENT_TYPE" => "application/json", input: payload)
    assert_equal(-32_009, JSON.parse(missing.body).dig("error", "code"))

    accepted = rack.post("/a2a?A2A-Version=1.0", "CONTENT_TYPE" => "application/json", input: payload)
    assert_equal 200, accepted.status
    assert JSON.parse(accepted.body).key?("result")
  end

  def test_rack_input_does_not_need_rewind
    adapter = build_adapter(lambda do |operation:, params:|
      { "tasks" => [], "totalSize" => 0, "pageSize" => 50, "nextPageToken" => "" }
    end)
    payload = JSON.generate(jsonrpc: "2.0", id: 9, method: "ListTasks", params: {})
    env = Rack::MockRequest.env_for(
      "/a2a",
      method: "POST",
      "CONTENT_TYPE" => "application/json",
      "HTTP_A2A_VERSION" => "1.0"
    )
    input = ReadOnlyInput.new(payload)
    refute input.respond_to?(:rewind)

    status, _headers, body = adapter.call(env.merge("rack.input" => input))

    assert_equal 200, status
    parsed = JSON.parse(body.join)
    assert_equal 9, parsed["id"]
    assert_equal 0, parsed.dig("result", "totalSize")
  end

  private

  def build_adapter(handler)
    A2A::Rails::Protocol::Agent2AgentAdapter.new(
      agent_card: AGENT_CARD,
      request_handler: handler
    )
  end
end
