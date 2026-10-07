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

  def test_async_task_returns_submitted_and_enqueues_selected_skill_without_running_handler_inline
    enqueued = []
    fake_job = Object.new
    fake_job.define_singleton_method(:perform_later) do |**arguments|
      enqueued << arguments
      Object.new.tap do |job|
        job.define_singleton_method(:enqueue_error) { nil }
      end
    end
    handler_called = false

    rack, lifecycle = build_stack(
      handler: ->(message:, context:) {
        handler_called = true
        "should run in job"
      },
      execution_mode: :async,
      task_job: fake_job,
      principal_id: "owner-1"
    )

    sent = rpc(rack, "SendMessage", send_params).dig("result", "task")

    assert_equal "TASK_STATE_SUBMITTED", sent.dig("status", "state")
    refute handler_called
    assert_equal 1, enqueued.length
    assert_equal sent.fetch("id"), enqueued.first.fetch(:task_id)
    assert_equal "owner-1", enqueued.first.fetch(:principal_id)
    assert_equal "reply", enqueued.first.fetch(:skill_id)
    assert_equal :submitted, lifecycle.find(sent.fetch("id")).dig(:status, :state)
  end

  def test_async_enqueue_failure_marks_task_failed_without_leaking_adapter_error
    fake_job = Object.new
    fake_job.define_singleton_method(:perform_later) do |**|
      raise "secret queue credential"
    end

    rack, lifecycle = build_stack(
      handler: ->(message:, context:) { "unused" },
      execution_mode: :async,
      task_job: fake_job
    )

    sent = rpc(rack, "SendMessage", send_params).dig("result", "task")

    assert_equal "TASK_STATE_FAILED", sent.dig("status", "state")
    assert_equal "Task execution failed", sent.dig("status", "message", "parts", 0, "text")
    refute_includes JSON.generate(sent), "secret queue credential"
    assert_equal :failed, lifecycle.find(sent.fetch("id")).dig(:status, :state)
  end

  def test_opt_in_direct_message_round_trips_through_real_sdk_without_creating_a_task
    rack, lifecycle = build_stack(
      handler: ->(message:, context:) {
        assert_nil context[:task_id]
        assert_equal "context-1", context[:context_id]
        "Direct: #{message.dig(:parts, 0, :text)}"
      },
      response_mode: :message
    )

    response = rpc(rack, "SendMessage", send_params).fetch("result")
    assert_equal ["message"], response.keys
    direct = response.fetch("message")
    assert_equal "ROLE_AGENT", direct.fetch("role")
    assert_equal "Direct: Hello", direct.dig("parts", 0, "text")
    assert_equal "context-1", direct.fetch("contextId")
    refute_empty direct.fetch("messageId")
    refute direct.key?("taskId")
    assert_equal 0, lifecycle.list.fetch(:total_size)
  end

  def test_message_mode_generates_context_id_when_absent
    rack, lifecycle = build_stack(handler: ->(message:, context:) {
      assert_nil context[:task_id]
      assert_kind_of String, context[:context_id]
      { "answer" => true }
    }, response_mode: :message)
    params = send_params
    params.fetch("message").delete("contextId")
    direct = rpc(rack, "SendMessage", params).dig("result", "message")

    refute_empty direct.fetch("contextId")
    assert_equal({ "answer" => true }, direct.dig("parts", 0, "data"))
    assert_equal 0, lifecycle.list.fetch(:total_size)
  end

  def test_callable_response_mode_allows_direct_message_and_legacy_task_in_one_agent
    rack, lifecycle = build_stack(
      handler: ->(message:, context:) { "reply" },
      response_mode: ->(message:) { message[:message_id] == "direct" ? :message : :task }
    )
    direct_params = send_params
    direct_params.fetch("message")["messageId"] = "direct"
    direct = rpc(rack, "SendMessage", direct_params).dig("result", "message")
    assert_equal "reply", direct.dig("parts", 0, "text")
    assert_equal 0, lifecycle.list.fetch(:total_size)

    task = rpc(rack, "SendMessage", send_params).dig("result", "task")
    assert_equal "TASK_STATE_COMPLETED", task.dig("status", "state")
    assert_equal "reply", task.dig("artifacts", 0, "parts", 0, "text")
    assert_equal 1, lifecycle.list.fetch(:total_size)
  end

  def test_direct_message_supports_file_part_using_existing_mapper
    file = A2A::Rails::FileArtifact.url(
      url: "https://files.example.test/result.txt", filename: "result.txt", media_type: "text/plain"
    )
    rack, lifecycle = build_stack(handler: ->(message:, context:) { file }, response_mode: :message)
    direct = rpc(rack, "SendMessage", send_params).dig("result", "message")
    part = direct.dig("parts", 0)
    assert_equal "https://files.example.test/result.txt", part.fetch("url")
    assert_equal "text/plain", part.fetch("mediaType")
    assert_equal "result.txt", part.fetch("filename")
    assert_equal 0, lifecycle.list.fetch(:total_size)
  end

  def test_invalid_direct_message_return_or_handler_error_has_sanitized_error
    [nil, Object.new].each do |result|
      rack, lifecycle = build_stack(handler: ->(message:, context:) { result }, response_mode: :message)
      response = rpc(rack, "SendMessage", send_params)
      assert_equal(-32_006, response.dig("error", "code"))
      refute response.key?("result")
      assert_equal 0, lifecycle.list.fetch(:total_size)
    end
    rack, lifecycle = build_stack(handler: ->(message:, context:) {
      raise "sensitive token from application"
    }, response_mode: :message)
    response = rpc(rack, "SendMessage", send_params)
    assert_equal(-32_006, response.dig("error", "code"))
    refute_includes JSON.generate(response), "sensitive token"
    assert_equal 0, lifecycle.list.fetch(:total_size)
  end

  def test_response_mode_selector_errors_do_not_leak_application_details_or_create_tasks
    [->(message:) { raise "secret token in response selector" }, ->(message:) { :unsupported }].each do |selector|
      rack, lifecycle = build_stack(handler: ->(message:, context:) { "not called" }, response_mode: selector)
      result = rpc(rack, "SendMessage", send_params)
      assert_equal(-32_006, result.dig("error", "code"))
      refute_includes JSON.generate(result), "secret token"
      assert_equal 0, lifecycle.list.fetch(:total_size)
    end
  end

  def test_file_raw_artifact_round_trips_through_real_sdk_and_task_queries
    file = A2A::Rails::FileArtifact.bytes(
      data: "binary\x00\xFF".b,
      filename: "output.txt",
      media_type: "text/plain"
    )
    rack, = build_stack(handler: ->(message:, context:) { file })
    sent = rpc(rack, "SendMessage", send_params).fetch("result").fetch("task")
    assert_equal "TASK_STATE_COMPLETED", sent.dig("status", "state")
    part = sent.dig("artifacts", 0, "parts", 0)

    assert_equal "output.txt", part.fetch("filename")
    assert_equal "text/plain", part.fetch("mediaType")
    assert_equal "YmluYXJ5AP8=", part.fetch("raw")
    refute part.key?("data")
    refute part.key?("url")

    get = rpc(rack, "GetTask", "id" => sent.fetch("id")).fetch("result")
    assert_equal part, get.dig("artifacts", 0, "parts", 0)

    list = rpc(rack, "ListTasks",
      "contextId" => sent.fetch("contextId"),
      "includeArtifacts" => true).fetch("result")
    assert_equal part, list.dig("tasks", 0, "artifacts", 0, "parts", 0)
  end

  def test_file_url_artifact_round_trips_through_real_sdk
    file = A2A::Rails::FileArtifact.url(
      url: "https://downloads.example.test/output.txt",
      filename: "output.txt",
      media_type: "text/plain"
    )
    rack, = build_stack(handler: ->(message:, context:) { file })
    sent = rpc(rack, "SendMessage", send_params).fetch("result").fetch("task")
    part = sent.dig("artifacts", 0, "parts", 0)

    assert_equal "https://downloads.example.test/output.txt", part.fetch("url")
    assert_equal "output.txt", part.fetch("filename")
    assert_equal "text/plain", part.fetch("mediaType")
    refute part.key?("raw")
    refute part.key?("data")
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

  def test_unsupported_push_notification_operations_have_dedicated_a2a_error
    rack, = build_stack(handler: ->(message:, context:) { "unused" })

    A2A::Rails::Protocol::Agent2AgentAdapter::PUSH_NOTIFICATION_OPERATIONS.each do |operation|
      response = rpc(rack, operation, {})
      assert_equal(-32_003, response.dig("error", "code"), operation)
      assert_match(/push notifications are not supported/i, response.dig("error", "message"), operation)
      refute response.key?("result"), operation
    end

    # Unsupported streaming remains a distinct operation error (-32004).
    streaming = rpc(rack, "SendStreamingMessage", "message" => send_params.fetch("message"))
    assert_equal(-32_004, streaming.dig("error", "code"))
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
      { "contextId" => ["wrong"] },
      { "includeArtifacts" => "true" }
    ].each do |changes|
      response = rpc(rack, "ListTasks", changes)
      assert response.key?("error"), "malformed ListTasks succeeded: #{changes.inspect}"
    end
  end

  private

  def build_stack(handler:, response_mode: :task, execution_mode: nil, task_job: A2A::Rails::TaskExecutionJob, principal_id: nil)
    agent = Class.new(A2A::Rails::Agent)
    agent.name "Integrated Test Agent"
    agent.description "Step 15-8"
    agent.version "1.0"
    agent.response_mode response_mode
    agent.execution_mode execution_mode if execution_mode
    agent.skill :reply,
      description: "Reply",
      tags: %w[test],
      handler: handler

    store = A2A::Rails::Task::MemoryStore.new
    lifecycle = A2A::Rails::Task::Lifecycle.new(store: store, principal_id: principal_id)
    request_handler = A2A::Rails::Protocol::RequestHandler.new(
      dispatcher: A2A::Rails::Dispatcher.new(agent: agent),
      lifecycle: lifecycle,
      task_job: task_job
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
