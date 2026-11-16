# frozen_string_literal: true

require_relative "../test_helper"
require "timeout"
require "json"

class TaskExecutionTurnTest < Minitest::Test
  class Handler
    class << self
      attr_accessor :calls, :behavior, :started, :release
    end

    def self.call(message:, context:)
      calls << [message, context]
      return A2A::Rails::InputRequired.new("Please answer again") if behavior == :question
      if behavior == :block || behavior == :block_fail || behavior == :block_reject
        started << true
        release.pop
        raise "private error" if behavior == :block_fail
        raise A2A::Rails::RejectedTask, "not allowed" if behavior == :block_reject
      end
      "answer: #{message.fetch(:message_id)}"
    end
  end

  class Agent < A2A::Rails::Agent
    name "Turn Job Agent"
    description "Turn job contract"
    version "1.0"
    execution_mode :async
    skill :reply, description: "Reply", tags: ["reply"], handler: Handler
  end

  def setup
    @configuration = A2A::Rails.instance_variable_get(:@configuration)
    @runtime = A2A::Rails.instance_variable_get(:@runtime)
    config = A2A::Rails::Configuration.new
    config.agent = "TaskExecutionTurnTest::Agent"
    config.task_execution_mode = :async
    A2A::Rails.instance_variable_set(:@configuration, config)
    @store = A2A::Rails::Task::MemoryStore.new
    A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new(store: @store))
    Handler.calls = []
    Handler.behavior = :success
    Handler.started = Queue.new
    Handler.release = Queue.new
    @task = {
      id: "turn-task", owner_id: "owner", context_id: "conversation",
      status: { state: :submitted, timestamp: Time.now.utc.iso8601(6) },
      history: [input_message("original"),
        { message_id: "question", role: :agent, parts: [{ text: "More information?" }] },
        input_message("answer")],
      execution: execution("turn-2", "answer")
    }
    @store.save(@task)
  end

  def teardown
    A2A::Rails.instance_variable_set(:@configuration, @configuration)
    A2A::Rails.instance_variable_set(:@runtime, @runtime)
    Handler.calls = []
  end

  def test_arguments_preserve_legacy_wire_shape_and_add_only_turn_identifier
    legacy = A2A::Rails::TaskExecutionArguments.new(**arguments.reject { |key, _| key == :turn_id })
    assert_equal A2A::Rails::TaskExecutionArguments::KEYS, legacy.to_h.keys
    assert_nil legacy.turn_id
    current = A2A::Rails::TaskExecutionArguments.new(**arguments)
    assert_equal "turn-2", current.turn_id
    assert current.turn_id.frozen?
    assert_equal "turn-2", JSON.parse(JSON.generate(current.to_h)).fetch("turn_id")
    ["", "bad\nvalue", "x" * 257, :symbol].each do |invalid|
      assert_raises(A2A::Rails::ConfigurationError) do
        A2A::Rails::TaskExecutionArguments.new(**arguments.merge(turn_id: invalid))
      end
    end
  end

  def test_deserialized_job_executes_its_message_not_history_first
    serialized = A2A::Rails::TaskExecutionJob.new(**arguments).serialize
    A2A::Rails::TaskExecutionJob.deserialize(serialized).perform_now
    task = saved
    assert_equal :completed, task.dig(:status, :state)
    assert_equal "answer: answer", task.dig(:artifacts, 0, :parts, 0, :text)
    current, context = Handler.calls.fetch(0)
    assert_equal "answer", current.fetch(:message_id)
    assert_equal "turn-2", context.fetch(:execution_turn_id)
    assert_equal "turn-task", context.fetch(:idempotency_key)
    assert_equal %w[original question answer], context.fetch(:history).map { |m| m.fetch(:message_id) }
    assert_equal "owner", context.fetch(:principal_id)
    current[:parts].first[:text] = "changed by application"
    context[:history].first[:parts].first[:text] = "changed by application"
    assert_equal "original", saved.fetch(:history).first.dig(:parts, 0, :text)
    assert_equal "answer", saved.fetch(:history).last.dig(:parts, 0, :text)
  end

  def test_input_required_releases_job_and_stale_duplicate_does_not_reenter
    Handler.behavior = :question
    perform
    waiting = saved
    assert_equal :input_required, waiting.dig(:status, :state)
    assert_equal "Please answer again", waiting.dig(:status, :message, :parts, 0, :text)
    assert_equal 4, waiting.fetch(:history).length
    perform
    assert_equal 1, Handler.calls.length
    assert_equal waiting, saved
  end

  def test_durable_string_role_is_accepted_without_changing_data_keys
    @task[:history].last[:role] = "user"
    @store.save(@task)
    perform
    assert_equal :completed, saved.dig(:status, :state)
    assert_equal "answer", Handler.calls.fetch(0).first.fetch(:message_id)
  end

  def test_old_turn_and_legacy_jobs_cannot_claim_new_turn
    before = saved
    perform(turn_id: "turn-1")
    perform(turn_id: nil)
    assert_empty Handler.calls
    assert_equal before, saved
    perform
    perform
    assert_equal 1, Handler.calls.length
  end

  def test_saved_skill_mismatch_never_invokes_handler
    perform(skill_id: "other")
    assert_empty Handler.calls
    assert_equal :failed, saved.dig(:status, :state)
  end

  def test_missing_turn_message_fails_safely_without_using_original_input
    @task[:execution][:message_id] = "missing"
    @store.save(@task)
    perform
    assert_empty Handler.calls
    assert_equal :failed, saved.dig(:status, :state)
  end

  def test_late_completion_failure_and_rejection_cannot_finish_a_newer_turn
    [:block, :block_fail, :block_reject].each do |behavior|
      @store.save(@task)
      Handler.calls = []
      Handler.behavior = behavior
      worker = Thread.new { perform }
      Timeout.timeout(5) { Handler.started.pop }
      advanced = saved
      advanced[:execution] = execution("turn-3", "third-answer")
      advanced[:history] << input_message("third-answer")
      advanced[:status] = { state: :submitted, timestamp: Time.now.utc.iso8601(6) }
      @store.save(advanced)
      expected = saved
      Handler.release << true
      assert worker.join(5), "old execution did not exit"
      worker.value
      assert_equal expected, saved, "late #{behavior} changed newer execution"
    ensure
      Handler.release << true if worker&.alive?
      worker&.join(2)
      worker&.kill if worker&.alive?
    end
  end

  def test_canceled_turn_cannot_be_revived_by_job
    @store.cancel("turn-task", principal_id: "owner")
    perform
    assert_empty Handler.calls
    assert_equal :canceled, saved.dig(:status, :state)
  end

  private

  def input_message(id)
    { message_id: id, role: :user, parts: [{ text: id, media_type: "text/plain" }], metadata: {} }
  end

  def execution(turn, message_id)
    { agent_class_name: Agent.name, skill_id: "reply", execution_mode: "async",
      turn_id: turn, message_id: message_id }
  end

  def arguments
    { task_id: "turn-task", principal_id: "owner", agent_class_name: Agent.name,
      skill_id: "reply", turn_id: "turn-2" }
  end

  def perform(**overrides)
    A2A::Rails::TaskExecutionJob.perform_now(**arguments.merge(overrides))
  end

  def saved
    @store.find("turn-task", principal_id: "owner")
  end
end
