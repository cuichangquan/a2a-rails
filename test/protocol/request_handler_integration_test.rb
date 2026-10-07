# frozen_string_literal: true

require "json"
require "rack/mock"
require_relative "../test_helper"

class RequestHandlerIntegrationTest < Minitest::Test
  AGENT_CARD = {
    "name" => "Integrated Test Agent",
    "description" => "a2a-rails Step 15-8 integration test",
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

  def test_send_get_and_list_use_real_sdk_and_internal_task_core
    rack, = build_stack(handler: lambda do |message:, context:|
      assert_equal :user, message[:role]
      assert_equal "Hello", message.dig(:parts, 0, :text)
      assert_equal "text/plain", message.dig(:parts, 0, :media_type)
      assert_equal :reply, context[:skill_id]
      "Echo: #{message.dig(:parts, 0, :text)}"
    end)

    sent = rpc(rack, "SendMessage", send_params).fetch("result").fetch("task")

    assert_equal "TASK_STATE_COMPLETED", sent.dig("status", "state")
    assert_equal "Echo: Hello", sent.dig("artifacts", 0, "parts", 0, "text")
    assert_equal "context-1", sent["contextId"]
    refute_empty sent["id"]

    fetched = rpc(rack, "GetTask", "id" => sent["id"]).fetch("result")
    assert_equal sent, fetched

    listed = rpc(
      rack,
      "ListTasks",
      "contextId" => "context-1",
      "status" => "TASK_STATE_COMPLETED",
      "historyLength" => 0
    ).fetch("result")
    assert_equal 1, listed["totalSize"]
    assert_equal [sent["id"]], listed["tasks"].map { |task| task["id"] }
    assert_equal [], listed.dig("tasks", 0, "history")
    refute listed.fetch("tasks").first.key?("artifacts")
  end

  def test_rejected_and_failed_tasks_are_valid_a2a_tasks
    rejected_rack, = build_stack(handler: lambda do |message:, context:|
      raise A2A::Rails::RejectedTask, "Request is not allowed"
    end)
    rejected = rpc(rejected_rack, "SendMessage", send_params).dig("result", "task")

    assert_equal "TASK_STATE_REJECTED", rejected.dig("status", "state")
    assert_equal "ROLE_AGENT", rejected.dig("status", "message", "role")
    assert_equal "Request is not allowed", rejected.dig("status", "message", "parts", 0, "text")

    failed_rack, = build_stack(handler: lambda do |message:, context:|
      raise "database exploded"
    end)
    failed = rpc(failed_rack, "SendMessage", send_params).dig("result", "task")

    assert_equal "TASK_STATE_FAILED", failed.dig("status", "state")
    assert_equal "Task execution failed", failed.dig("status", "message", "parts", 0, "text")
    refute_includes JSON.generate(failed), "database exploded"
  end

  def test_cancel_and_task_errors_translate_to_sdk_errors
    rack, lifecycle = build_stack(handler: ->(message:, context:) { "unused" })
    task = lifecycle.create(message: internal_message, context_id: "context-manual")
    lifecycle.start(task[:id])

    canceled = rpc(rack, "CancelTask", "id" => task[:id]).fetch("result")
    assert_equal "TASK_STATE_CANCELED", canceled.dig("status", "state")
    assert_equal(-32_002, rpc(rack, "CancelTask", "id" => task[:id]).dig("error", "code"))
    assert_equal(-32_001, rpc(rack, "GetTask", "id" => "missing").dig("error", "code"))
    assert_equal(-32_602, rpc(rack, "GetTask", {}).dig("error", "code"))
  end

  def test_cancel_wins_over_late_send_completion
    started = Queue.new
    release = Queue.new
    rack, _lifecycle, adapter = build_stack(handler: lambda do |message:, context:|
      started << context.fetch(:task_id)
      release.pop
      "late result"
    end)

    worker = Thread.new do
      Rack::MockRequest.new(adapter).post(
        "/a2a",
        "CONTENT_TYPE" => "application/json",
        "HTTP_A2A_VERSION" => "1.0",
        input: JSON.generate(jsonrpc: "2.0", id: "worker", method: "SendMessage", params: send_params)
      )
    end

    task_id = started.pop
    canceled = rpc(rack, "CancelTask", "id" => task_id).fetch("result")
    assert_equal "TASK_STATE_CANCELED", canceled.dig("status", "state")

    release << true
    sent = JSON.parse(worker.value.body).fetch("result").fetch("task")
    assert_equal "TASK_STATE_CANCELED", sent.dig("status", "state")
    refute sent.key?("artifacts")
  ensure
    release << true if release && worker&.alive?
    worker&.join(2)
    worker&.kill if worker&.alive?
  end

  def test_task_continuation_and_non_text_parts_are_rejected_at_protocol_boundary
    rack, lifecycle = build_stack(handler: ->(message:, context:) { "unused" })
    task = lifecycle.create(message: internal_message, context_id: "context-existing")

    continuation = send_params
    continuation["message"]["taskId"] = task[:id]
    assert_equal(-32_004, rpc(rack, "SendMessage", continuation).dig("error", "code"))

    unsupported = send_params
    unsupported["message"]["parts"] = [{ "data" => { "x" => 1 } }]
    refute_nil rpc(rack, "SendMessage", unsupported).dig("error", "code")
  end

  def test_list_validation_uses_internal_store_rules_through_sdk_boundary
    rack, = build_stack(handler: ->(message:, context:) { "ok" })

    assert_equal(-32_602, rpc(rack, "ListTasks", "pageSize" => 0).dig("error", "code"))
    assert_equal(-32_602, rpc(rack, "ListTasks", "historyLength" => -1).dig("error", "code"))
    assert_equal(-32_602, rpc(rack, "ListTasks", "statusTimestampAfter" => "bad").dig("error", "code"))
  end

  def test_malformed_message_and_task_query_fields_fail_before_task_creation
    rack, lifecycle = build_stack(handler: ->(message:, context:) { "should not execute" })

    malformed_messages = [
      { "metadata" => "secret-raw-metadata" },
      { "contextId" => ["not", "a", "string"] },
      { "taskId" => 101 },
      { "parts" => [{ "text" => "hello", "mediaType" => 5 }] },
      { "parts" => [{ "text" => "hello", "metadata" => ["bad"] }] }
    ]
    malformed_messages.each do |changes|
      input = send_params
      input.fetch("message").merge!(changes)
      response = rpc(rack, "SendMessage", input)
      assert response.key?("error"), "malformed Message created a Task: #{changes.inspect}"
      refute response.key?("result")
    end

    assert_equal 0, lifecycle.list.fetch(:total_size)

    [
      { "pageToken" => 123 },
      { "pageToken" => nil },
      { "contextId" => ["wrong"] },
      { "includeArtifacts" => "true" }
    ].each do |changes|
      response = rpc(rack, "ListTasks", changes)
      assert response.key?("error"), "malformed ListTasks succeeded: #{changes.inspect}"
    end
  end

  private

  def build_stack(handler:)
    agent = Class.new(A2A::Rails::Agent)
    agent.name "Integrated Test Agent"
    agent.description "Step 15-8"
    agent.version "1.0"
    agent.skill :reply,
      description: "Reply",
      tags: %w[test],
      handler: handler

    store = A2A::Rails::Task::MemoryStore.new
    lifecycle = A2A::Rails::Task::Lifecycle.new(store: store)
    request_handler = A2A::Rails::Protocol::RequestHandler.new(
      dispatcher: A2A::Rails::Dispatcher.new(agent: agent),
      lifecycle: lifecycle
    )
    adapter = A2A::Rails::Protocol::Agent2AgentAdapter.new(
      agent_card: AGENT_CARD,
      request_handler: request_handler
    )

    [Rack::MockRequest.new(adapter), lifecycle, adapter]
  end

  def rpc(rack, method, params)
    response = rack.post(
      "/a2a",
      "CONTENT_TYPE" => "application/json",
      "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(jsonrpc: "2.0", id: "step-15-8", method: method, params: params)
    )
    assert_equal 200, response.status
    JSON.parse(response.body)
  end

  def send_params
    {
      "message" => {
        "messageId" => "message-1",
        "role" => "ROLE_USER",
        "contextId" => "context-1",
        "parts" => [{ "text" => "Hello" }]
      }
    }
  end

  def internal_message
    {
      message_id: "manual-message",
      role: :user,
      parts: [{ text: "Hold", media_type: "text/plain" }],
      metadata: {}
    }
  end
end
