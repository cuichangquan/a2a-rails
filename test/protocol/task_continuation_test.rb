# frozen_string_literal: true

require "json"
require "rack/mock"
require_relative "../test_helper"

class TaskContinuationTest < Minitest::Test
  def setup
    @calls = []
    @route_calls = 0
    @store = A2A::Rails::Task::MemoryStore.new
    @lifecycle = A2A::Rails::Task::Lifecycle.new(store: @store, principal_id: "owner")
    @handler = lambda do |message:, context:|
      @calls << [Marshal.load(Marshal.dump(message)), Marshal.load(Marshal.dump(context))]
      if message.dig(:parts, 0, :text) == "done"
        { "state" => "input_required", "false" => false, "null" => nil }
      else
        A2A::Rails::InputRequired.new("Answer again", data: payload)
      end
    end
    @agent = Class.new(A2A::Rails::Agent)
    @agent.name "Continuation Agent"
    @agent.description "Continuation test"
    @agent.version "1.0"
    @agent.skill :first, description: "First", tags: ["test"], handler: @handler,
      input_modes: ["text/plain", "application/json"], output_modes: ["text/plain", "application/json"]
    @agent.skill :other, description: "Other", tags: ["test"], handler: ->(**) { raise "rerouted" }
    @agent.router lambda { |**| @route_calls += 1; @route_calls == 1 ? :first : :other }
    @rack = stack(@lifecycle)
  end

  def test_real_sdk_multiturn_questions_data_and_stable_route
    first = send_message("m1", "start", historyLength: 0).fetch("result").fetch("task")
    id = first.fetch("id")
    assert_equal "TASK_STATE_INPUT_REQUIRED", first.dig("status", "state")
    assert_equal [], first.fetch("history")
    assert_equal payload, first.dig("status", "message", "parts", 1, "data")
    assert_equal id, first.dig("status", "message", "taskId")
    second = send_message("m2", "more", taskId: id).fetch("result").fetch("task")
    assert_equal "TASK_STATE_INPUT_REQUIRED", second.dig("status", "state")
    assert_equal 4, second.fetch("history").length
    assert_equal payload, second.dig("history", 1, "parts", 1, "data")
    final = send_message("m3", "done", taskId: id).fetch("result").fetch("task")
    assert_equal id, final.fetch("id")
    assert_equal first.fetch("contextId"), final.fetch("contextId")
    assert_equal "TASK_STATE_COMPLETED", final.dig("status", "state")
    assert_equal "input_required", final.dig("artifacts", 0, "parts", 0, "data", "state")
    assert_equal 1, @route_calls
    assert_equal 3, @calls.length
    assert_equal [1, 3, 5], @calls.map { |_, context| context.fetch(:history).length }
    assert_equal 3, @calls.map { |_, context| context.fetch(:execution_turn_id) }.uniq.length
    assert_equal [id], @calls.map { |_, context| context.fetch(:idempotency_key) }.uniq
  end

  def test_same_answer_replay_is_not_executed_and_conflicting_id_is_rejected
    id = send_message("m1", "start").dig("result", "task", "id")
    final = send_message("m2", "done", taskId: id).fetch("result")
    assert_equal final, send_message("m2", "done", taskId: id).fetch("result")
    assert_equal 2, @calls.length
    assert_equal(-32_602, send_message("m2", "different", taskId: id).dig("error", "code"))
    assert_equal(-32_004, send_message("m3", "done", taskId: id).dig("error", "code"))
  end

  def test_context_mismatch_and_foreign_tasks_do_not_change_history
    id = send_message("m1", "start").dig("result", "task", "id")
    assert_equal(-32_602, send_message("m2", "done", taskId: id, contextId: "wrong").dig("error", "code"))
    foreign = stack(A2A::Rails::Task::Lifecycle.new(store: @store, principal_id: "other"))
    missing = rpc(foreign, "SendMessage", params("m2", "done", taskId: "missing"))
    denied = rpc(foreign, "SendMessage", params("m2", "done", taskId: id))
    assert_equal missing.dig("error", "code"), denied.dig("error", "code")
    assert_equal(-32_001, denied.dig("error", "code"))
    assert_equal 2, @lifecycle.find(id).fetch(:history).length
  end

  def test_input_required_is_gettable_listable_cancelable
    id = send_message("m1", "start").dig("result", "task", "id")
    assert_equal "TASK_STATE_INPUT_REQUIRED", rpc(@rack, "GetTask", {"id" => id}).dig("result", "status", "state")
    assert_equal 1, rpc(@rack, "ListTasks", {"status" => "TASK_STATE_INPUT_REQUIRED"}).dig("result", "totalSize")
    assert_equal "TASK_STATE_CANCELED", rpc(@rack, "CancelTask", {"id" => id}).dig("result", "status", "state")
    assert_equal(-32_004, send_message("m2", "done", taskId: id).dig("error", "code"))
  end

  def test_direct_message_does_not_create_task_for_input_required
    @agent.response_mode :message
    result = send_message("m1", "start")
    assert result.key?("error")
    assert_equal 0, @lifecycle.list.fetch(:total_size)
  end

  def test_protocol_core_contains_no_sdk_exception_requirement
    @agent.response_mode ->(**) { raise "private secret" }
    handler = A2A::Rails::Protocol::RequestHandler.new(
      dispatcher: A2A::Rails::Dispatcher.new(agent: @agent), lifecycle: @lifecycle)
    error = assert_raises(A2A::Rails::InvalidAgentResponseError) do
      handler.call(operation: "SendMessage", params: params("m1", "start"))
    end
    refute_includes error.message, "private secret"
  end

  private

  def payload
    {"messageId" => "camel", "message_id" => "snake", "false" => false,
     "null" => nil, "empty" => {}, "nested" => [[false, nil, {}]]}
  end

  def stack(lifecycle)
    handler = A2A::Rails::Protocol::RequestHandler.new(
      dispatcher: A2A::Rails::Dispatcher.new(agent: @agent), lifecycle: lifecycle)
    card = A2A::Rails::AgentCard::Builder.new(agent: @agent, public_base_url: "http://example.test").call
    Rack::MockRequest.new(A2A::Rails::Protocol::Agent2AgentAdapter.new(agent_card: card, request_handler: handler))
  end

  def params(message_id, text, **fields)
    {"message" => {"messageId" => message_id, "role" => "ROLE_USER", "parts" => [{"text" => text}]}.merge(fields.transform_keys(&:to_s))}
  end

  def send_message(message_id, text, historyLength: nil, **fields)
    input = params(message_id, text, **fields)
    input["configuration"] = {"historyLength" => historyLength} unless historyLength.nil?
    rpc(@rack, "SendMessage", input)
  end

  def rpc(rack, method, input)
    response = rack.post("/a2a", "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(jsonrpc: "2.0", id: "continuation", method: method, params: input))
    assert_equal 200, response.status
    JSON.parse(response.body)
  end
end
