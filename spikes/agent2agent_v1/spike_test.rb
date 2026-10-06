# frozen_string_literal: true

require "minitest/autorun"
require "rack/mock"
require_relative "app"

class Agent2AgentV1SpikeTest < Minitest::Test
  def setup
    @app = Agent2AgentV1Spike::App.new
    @rack = Rack::MockRequest.new(@app)
  end

  def rpc(method, params = nil, version: "1.0", path: "/a2a", id: "probe-1", **wire_params)
    params ||= wire_params
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["HTTP_A2A_VERSION"] = version unless version.nil?
    response = @rack.post(path, headers.merge(input: JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)))
    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal id, body["id"]
    assert_equal "2.0", body["jsonrpc"]
    body
  end

  def send_params(context_id = "context-1")
    { "message" => { "messageId" => SecureRandom.uuid, "role" => "ROLE_USER", "contextId" => context_id,
      "parts" => [{ "text" => "Hello" }] } }
  end

  def seed(id, state: "TASK_STATE_WORKING", timestamp: "2026-10-06T00:00:00Z", context: "seed")
    @app.store.save("id" => id, "contextId" => context, "status" => { "state" => state, "timestamp" => timestamp },
      "history" => [send_params.fetch("message"), send_params.fetch("message")],
      "artifacts" => [{ "artifactId" => "artifact-#{id}", "parts" => [{ "text" => id }] }])
  end

  def test_exact_sdk_and_agent_card
    assert_equal "2.0.0", Gem.loaded_specs.fetch("agent2agent").version.to_s
    assert_kind_of A2A::Server, @app.sdk
    response = @rack.get("/.well-known/agent-card.json")
    assert_equal 200, response.status
    card = JSON.parse(response.body)
    assert A2A::Protocol::JsonSchema["Agent Card"].new(card).valid?
    assert_equal [{ "url" => "http://localhost:9292/a2a", "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" }], card["supportedInterfaces"]
    assert_equal({ "streaming" => false, "pushNotifications" => false, "extendedAgentCard" => false }, card["capabilities"])
  end

  def test_send_and_get_task
    sent = rpc("SendMessage", send_params).fetch("result").fetch("task")
    assert_equal "TASK_STATE_COMPLETED", sent.dig("status", "state")
    assert_equal "Echo: Hello", sent.dig("artifacts", 0, "parts", 0, "text")
    assert_equal "context-1", sent["contextId"]
    refute_empty sent["id"]
    refute_empty sent.dig("artifacts", 0, "artifactId")
    assert_equal sent, rpc("GetTask", "id" => sent["id"]).fetch("result")
  end

  def test_sdk_independent_handler_boundary
    seen = nil
    @app = Agent2AgentV1Spike::App.new(handler: ->(message:, context:) { seen = [message, context]; "ok" })
    @rack = Rack::MockRequest.new(@app)
    task = rpc("SendMessage", send_params).fetch("result").fetch("task")
    assert_kind_of Hash, seen[0]
    assert_equal :user, seen[0][:role]
    assert_equal [{ text: "Hello" }], seen[0][:parts]
    assert_equal({ task_id: task["id"], context_id: "context-1", skill_id: :reply }, seen[1])
  end

  def test_generated_context
    params = send_params
    params["message"].delete("contextId")
    refute_empty rpc("SendMessage", params).dig("result", "task", "contextId")
  end

  def test_not_found_and_missing_id
    %w[GetTask CancelTask].each do |method|
      assert_equal(-32001, rpc(method, "id" => "missing").dig("error", "code"))
      assert_equal(-32602, rpc(method).dig("error", "code"))
    end
  end

  def test_cancel_working_and_all_terminal_states
    seed("working")
    canceled = rpc("CancelTask", "id" => "working").fetch("result")
    assert_equal "TASK_STATE_CANCELED", canceled.dig("status", "state")
    assert_equal canceled, rpc("GetTask", "id" => "working").fetch("result")
    Agent2AgentV1Spike::MemoryStore::TERMINAL.each do |state|
      seed(state, state: state)
      assert_equal(-32002, rpc("CancelTask", "id" => state).dig("error", "code"))
    end
  end

  def test_cancellation_is_not_overwritten_by_handler_completion
    started, release = Queue.new, Queue.new
    @app = Agent2AgentV1Spike::App.new(handler: ->(message:, context:) { started << context[:task_id]; release.pop; "late result" })
    @rack = Rack::MockRequest.new(@app)
    worker = Thread.new do
      Rack::MockRequest.new(@app).post("/a2a", "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0",
        input: JSON.generate(jsonrpc: "2.0", id: 1, method: "SendMessage", params: send_params))
    end
    id = started.pop
    assert_equal "TASK_STATE_CANCELED", rpc("CancelTask", "id" => id).dig("result", "status", "state")
    release << true
    result = JSON.parse(worker.value.body).fetch("result").fetch("task")
    assert_equal "TASK_STATE_CANCELED", result.dig("status", "state")
    refute result.key?("artifacts")
  ensure
    release << true if release
    worker&.join(2)
    worker&.kill if worker&.alive?
  end

  def test_list_empty_and_defaults
    result = rpc("ListTasks").fetch("result")
    assert_equal({ "tasks" => [], "totalSize" => 0, "pageSize" => 50, "nextPageToken" => "" }, result)
  end

  def test_list_filters_projection_and_pagination
    seed("old", timestamp: "2026-10-06T00:00:00Z")
    seed("new", timestamp: "2026-10-06T01:00:00Z")
    seed("other", context: "other")
    query = { "contextId" => "seed", "status" => "TASK_STATE_WORKING", "pageSize" => 1, "historyLength" => 0 }
    first = rpc("ListTasks", query).fetch("result")
    assert_equal 2, first["totalSize"]
    assert_equal 1, first["pageSize"]
    assert_equal ["new"], first["tasks"].map { |t| t["id"] }
    assert_equal [], first.dig("tasks", 0, "history")
    refute first["tasks"][0].key?("artifacts")
    refute_empty first["nextPageToken"]
    seed("newer", timestamp: "2026-10-06T02:00:00Z")
    second = rpc("ListTasks", query.merge("pageToken" => first["nextPageToken"])).fetch("result")
    assert_equal ["old"], second["tasks"].map { |t| t["id"] }
    assert_equal 2, second["totalSize"]
    assert_equal "", second["nextPageToken"]
    assert_equal(-32602, rpc("ListTasks", query.merge("pageToken" => first["nextPageToken"], "contextId" => "other")).dig("error", "code"))
  end

  def test_timestamp_filter_is_inclusive_and_artifacts_opt_in
    seed("old")
    seed("new", timestamp: "2026-10-06T01:00:00Z")
    tasks = rpc("ListTasks", "statusTimestampAfter" => "2026-10-06T01:00:00Z", "includeArtifacts" => true, "historyLength" => 1).dig("result", "tasks")
    assert_equal ["new"], tasks.map { |t| t["id"] }
    assert_equal 1, tasks[0]["history"].length
    refute_empty tasks[0]["artifacts"]
  end

  def test_list_invalid_parameters
    [0, 101, -1, "bad"].each { |size| assert_equal(-32602, rpc("ListTasks", "pageSize" => size).dig("error", "code")) }
    [{ "pageToken" => "bad" }, { "historyLength" => -1 }, { "statusTimestampAfter" => "bad" }].each do |params|
      assert_equal(-32602, rpc("ListTasks", params).dig("error", "code"))
    end
  end

  def test_get_history_projection_does_not_mutate_store
    seed("history")
    assert_equal [], rpc("GetTask", "id" => "history", "historyLength" => 0).dig("result", "history")
    assert_equal 1, rpc("GetTask", "id" => "history", "historyLength" => 1).dig("result", "history").length
    assert_equal 2, rpc("GetTask", "id" => "history").dig("result", "history").length
  end

  def test_versions_and_query_parameter
    [nil, "", "0.3", "0.5", "2.0"].each do |version|
      assert_equal(-32009, rpc("ListTasks", version: version).dig("error", "code"))
    end
    assert rpc("ListTasks", version: nil, path: "/a2a?A2A-Version=1.0").key?("result")
  end

  def test_disabled_capabilities
    %w[SendStreamingMessage SubscribeToTask].each do |method|
      assert_equal(-32004, rpc(method).dig("error", "code"))
    end
    %w[CreateTaskPushNotificationConfig GetTaskPushNotificationConfig ListTaskPushNotificationConfigs DeleteTaskPushNotificationConfig].each do |method|
      assert_equal(-32003, rpc(method).dig("error", "code"))
    end
    assert_equal(-32007, rpc("GetExtendedAgentCard").dig("error", "code"))
  end

  def test_http_surface
    %w[/rest /a2a/rest /grpc /a2a/grpc /a2a/.well-known/agent-card.json /a2a/].each do |path|
      assert_equal 404, @rack.get(path).status
      assert_equal 404, @rack.post(path).status
    end
    assert_equal 405, @rack.get("/a2a").status
    assert_equal 405, @rack.post("/.well-known/agent-card.json").status
    assert_equal 415, @rack.post("/a2a", "CONTENT_TYPE" => "text/plain").status
    response = @rack.post("/a2a", "CONTENT_TYPE" => "application/json; charset=utf-8", "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(jsonrpc: "2.0", id: 1, method: "ListTasks", params: {}))
    assert_equal "1.0", response["a2a-version"]
    assert JSON.parse(response.body).key?("result")
  end

  def test_invalid_message_and_parse_error
    assert_equal(-32602, rpc("SendMessage").dig("error", "code"))
    params = send_params
    params["message"].delete("messageId")
    assert_equal(-32602, rpc("SendMessage", params).dig("error", "code"))
    response = @rack.post("/a2a", "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0", input: "{")
    assert_equal(-32700, JSON.parse(response.body).dig("error", "code"))
  end
end
