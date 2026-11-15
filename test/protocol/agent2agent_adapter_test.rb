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

  def test_data_input_preserves_json_values_and_keys_before_handler
    seen = nil
    adapter = build_adapter(lambda do |operation:, params:|
      seen = params
      { "message" => wire_message([{ "text" => "received" }], role: "ROLE_AGENT") }
    end)
    data = json_data
    params = { "message" => wire_message([
      { "data" => data, "mediaType" => "application/json", "metadata" => { "removed" => nil, "kept" => false } }
    ]) }

    response = rpc(adapter, "SendMessage", params)

    assert response.key?("result"), response.inspect
    part = seen.dig("message", "parts", 0)
    assert_equal data, part.fetch("data")
    assert part.fetch("data").key?("nullable")
    assert_equal "application/json", part.fetch("mediaType")
    # Existing SDK metadata compaction is intentionally outside this change.
    assert_equal({ "kept" => false }, part.fetch("metadata"))
  end

  def test_original_kind_field_presence_reaches_rails_input_contract
    seen = []
    adapter = build_adapter(lambda do |operation:, params:|
      seen << params.dig("message", "parts", 0)
      { "message" => wire_message([{ "text" => "received" }], role: "ROLE_AGENT") }
    end)
    parts = [
      { "text" => "x", "data" => nil },
      { "data" => {}, "text" => nil },
      { "data" => {}, "raw" => nil },
      { "data" => {}, "url" => nil },
      { "data" => nil },
      { "data" => {}, "mediaType" => nil }
    ]

    parts.each do |part|
      response = rpc(adapter, "SendMessage", "message" => wire_message([part]))
      assert response.key?("result"), response.inspect
    end

    # A stub captures the adapter boundary only. RequestHandler decides which
    # ordinary invalid Part shapes to reject before running a business Handler.
    assert_equal parts, seen
  end

  def test_data_media_type_alias_and_text_only_sdk_behavior_are_retained
    seen = nil
    adapter = build_adapter(lambda do |operation:, params:|
      seen = params
      { "message" => wire_message([{ "text" => "received" }], role: "ROLE_AGENT") }
    end)
    rpc(adapter, "SendMessage", "message" => wire_message([
      { "data" => {}, "media_type" => nil },
      { "text" => "existing", "mediaType" => nil, "metadata" => { "removed" => nil, "kept" => false } }
    ]))

    assert_equal({ "data" => {}, "mediaType" => nil }, seen.dig("message", "parts", 0))
    assert_equal({ "text" => "existing", "metadata" => { "kept" => false } }, seen.dig("message", "parts", 1))
  end

  def test_data_output_preserves_objects_and_existing_array_results_in_all_response_paths
    [json_data, [json_data, nil, false, [], {}]].each do |data|
      message = wire_message([{ "data" => data, "metadata" => { "removed" => nil, "kept" => false } }], role: "ROLE_AGENT")
      task = wire_task(data)
      responses = {
        "SendMessage" => [{ "message" => message }, { "task" => task }],
        "GetTask" => [task],
        "CancelTask" => [task],
        "ListTasks" => [{ "tasks" => [task], "totalSize" => 1, "pageSize" => 50, "nextPageToken" => "" }]
      }

      responses.each do |operation, results|
        results.each do |result|
          before = Marshal.load(Marshal.dump(result))
          adapter = build_adapter(->(operation:, params:) { result })
          params = operation == "SendMessage" ? { "message" => wire_message([{ "text" => "request" }]) } : {}
          response = rpc(adapter, operation, params).fetch("result")
          output_message = response["message"]
          if output_message
            part = output_message.fetch("parts").first
            assert_equal data, part.fetch("data")
            assert_equal({ "kept" => false }, part.fetch("metadata"))
          else
            output_task = response["task"] || response.fetch("tasks", [response]).first
            assert_equal data, output_task.dig("history", 0, "parts", 0, "data")
            assert_equal data, output_task.dig("artifacts", 0, "parts", 0, "data")
            assert_equal data, output_task.dig("status", "message", "parts", 0, "data")
          end
          assert_equal before, result, "response restoration must not modify application results"
        end
      end
    end
  end

  def test_data_preservation_does_not_skip_sdk_request_validation
    called = false
    adapter = build_adapter(lambda do |operation:, params:|
      called = true
      { "message" => wire_message([{ "text" => "unexpected" }], role: "ROLE_AGENT") }
    end)
    message = wire_message([{ "data" => json_data }]).merge("messageId" => 7)

    response = rpc(adapter, "SendMessage", "message" => message)

    assert_equal(-32_602, response.dig("error", "code"))
    refute called
  end

  def test_data_preservation_does_not_skip_sdk_response_validation
    adapter = build_adapter(->(operation:, params:) { {} })
    message = wire_message([{ "data" => json_data }], role: "ROLE_AGENT").merge("messageId" => 7)

    assert_raises(A2A::Protocol::JsonSchema::ValidationError) do
      adapter.send(:schema, "Send Message Response", "message" => message)
    end
  end

  private

  def json_data
    {
      "messageId" => "camel", "message_id" => "snake", "nullable" => nil,
      "false" => false, "empty" => {}, "nested" => [[nil, { "nullable" => nil }]],
      "message" => { "parts" => [{ "data" => { "nullable" => nil } }] }
    }
  end

  def wire_message(parts, role: "ROLE_USER")
    { "messageId" => "data-message", "role" => role, "parts" => parts }
  end

  def wire_task(data)
    message = wire_message([{ "data" => data }], role: "ROLE_AGENT")
    {
      "id" => "data-task", "contextId" => "data-context",
      "status" => { "state" => "TASK_STATE_COMPLETED", "message" => message },
      "history" => [message], "artifacts" => [{ "artifactId" => "data-artifact", "parts" => [{ "data" => data }] }]
    }
  end

  def rpc(adapter, operation, params)
    response = Rack::MockRequest.new(adapter).post(
      "/a2a", "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(jsonrpc: "2.0", id: "data-boundary", method: operation, params: params)
    )
    assert_equal 200, response.status
    assert_equal "1.0", response["a2a-version"]
    body = JSON.parse(response.body)
    assert_equal "data-boundary", body.fetch("id")
    body
  end

  def build_adapter(handler)
    A2A::Rails::Protocol::Agent2AgentAdapter.new(
      agent_card: AGENT_CARD,
      request_handler: handler
    )
  end
end
