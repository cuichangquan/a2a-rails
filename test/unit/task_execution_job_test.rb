# frozen_string_literal: true

require_relative "../test_helper"

class TaskExecutionJobTest < Minitest::Test
  class Handler
    class << self
      attr_accessor :calls, :behavior, :started, :release
    end

    def self.call(message:, context:)
      self.calls ||= []
      calls << [message, context]

      case behavior
      when :fail
        raise "sensitive handler failure"
      when :reject
        raise A2A::Rails::RejectedTask, "Request is not allowed"
      when :block
        started << context.fetch(:task_id)
        release.pop
        "late job result"
      else
        "job result"
      end
    end
  end

  class AsyncAgent < A2A::Rails::Agent
    name "Async Job Agent"
    description "Runs a Task through ActiveJob"
    version "1.0"
    execution_mode :async
    skill :reply, description: "Reply", tags: ["reply"], handler: Handler
  end

  def setup
    @original_configuration = A2A::Rails.instance_variable_get(:@configuration)
    @original_runtime = A2A::Rails.instance_variable_get(:@runtime)

    configuration = A2A::Rails::Configuration.new
    configuration.agent = "TaskExecutionJobTest::AsyncAgent"
    configuration.task_execution_mode = :async
    A2A::Rails.instance_variable_set(:@configuration, configuration)

    @store = A2A::Rails::Task::MemoryStore.new
    A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new(store: @store))

    Handler.calls = []
    Handler.behavior = :success
    Handler.started = Queue.new
    Handler.release = Queue.new
    @lifecycle = A2A::Rails::Task::Lifecycle.new(
      store: @store,
      principal_id: "owner-1"
    )
    @task = @lifecycle.create(
      message: {
        message_id: "message-1",
        role: :user,
        parts: [{ text: "Hello", media_type: "text/plain" }],
        metadata: {}
      },
      context_id: "context-1"
    )
  end

  def teardown
    A2A::Rails.instance_variable_set(:@configuration, @original_configuration)
    A2A::Rails.instance_variable_set(:@runtime, @original_runtime)
    Handler.calls = []
    Handler.behavior = :success
    Handler.started = nil
    Handler.release = nil
  end

  def test_task_job_forces_immediate_enqueue_boundary
    assert_equal false, A2A::Rails::TaskExecutionJob.enqueue_after_transaction_commit
  end

  def test_perform_claims_executes_selected_skill_and_completes_task
    perform_task

    final = @lifecycle.find(@task.fetch(:id))
    assert_equal :completed, final.dig(:status, :state)
    assert_equal "job result", final.dig(:artifacts, 0, :parts, 0, :text)
    assert_equal 1, Handler.calls.length

    message, context = Handler.calls.first
    assert_equal "message-1", message.fetch(:message_id)
    assert_equal :reply, context.fetch(:skill_id)
    assert_equal "owner-1", context.fetch(:principal_id)
    assert_equal @task.fetch(:id), context.fetch(:idempotency_key)
    assert_equal @task.fetch(:id), context.fetch(:task_id)
    assert_equal "context-1", context.fetch(:context_id)
  end

  def test_handler_failure_becomes_failed_without_generic_retry
    Handler.behavior = :fail

    perform_task

    failed = @lifecycle.find(@task.fetch(:id))
    assert_equal :failed, failed.dig(:status, :state)
    assert_equal "Task execution failed", failed.dig(:status, :message)
    assert_equal 1, Handler.calls.length

    # A later duplicate delivery sees the terminal Task and cannot execute
    # the Handler again.
    perform_task
    assert_equal 1, Handler.calls.length
  end

  def test_rejected_handler_becomes_rejected_without_retry
    Handler.behavior = :reject

    perform_task

    rejected = @lifecycle.find(@task.fetch(:id))
    assert_equal :rejected, rejected.dig(:status, :state)
    assert_equal "Request is not allowed", rejected.dig(:status, :message)
    assert_equal 1, Handler.calls.length
  end

  def test_duplicate_delivery_does_not_execute_handler_twice
    perform_task
    perform_task

    assert_equal 1, Handler.calls.length
    assert_equal :completed, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)
  end

  def test_cancel_while_handler_is_working_wins_over_late_job_completion
    Handler.behavior = :block
    worker = Thread.new { perform_task }

    task_id = Handler.started.pop
    assert_equal @task.fetch(:id), task_id
    assert_equal :working, @lifecycle.find(task_id).dig(:status, :state)

    canceled = @lifecycle.cancel(task_id)
    assert_equal :canceled, canceled.dig(:status, :state)

    Handler.release << true
    worker.join(2)
    refute worker.alive?

    final = @lifecycle.find(task_id)
    assert_equal :canceled, final.dig(:status, :state)
    refute final.key?(:artifacts)
    assert_equal 1, Handler.calls.length
  ensure
    Handler.release << true if Handler.release && worker&.alive?
    worker&.join(2)
    worker&.kill if worker&.alive?
  end

  def test_cancel_before_job_delivery_prevents_handler_start
    @lifecycle.cancel(@task.fetch(:id))

    perform_task

    assert_empty Handler.calls
    assert_equal :canceled, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)
  end

  def test_foreign_principal_cannot_claim_or_execute_task
    A2A::Rails::TaskExecutionJob.perform_now(
      task_id: @task.fetch(:id),
      principal_id: "owner-2",
      agent_class_name: AsyncAgent.name,
      skill_id: "reply"
    )

    assert_empty Handler.calls
    assert_equal :submitted, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)

    perform_task

    assert_equal 1, Handler.calls.length
    assert_equal :completed, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)
  end

  def test_invalid_serialized_principal_does_not_mutate_task
    A2A::Rails::TaskExecutionJob.perform_now(
      task_id: @task.fetch(:id),
      principal_id: "owner-1\nAuthorization: Bearer secret",
      agent_class_name: AsyncAgent.name,
      skill_id: "reply"
    )

    assert_empty Handler.calls
    assert_equal :submitted, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)
  end

  def test_agent_mismatch_fails_claimed_task_without_running_handler
    A2A::Rails::TaskExecutionJob.perform_now(
      task_id: @task.fetch(:id),
      principal_id: "owner-1",
      agent_class_name: "OtherAgent",
      skill_id: "reply"
    )

    assert_empty Handler.calls
    assert_equal :failed, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)
  end

  private

  def perform_task
    A2A::Rails::TaskExecutionJob.perform_now(
      task_id: @task.fetch(:id),
      principal_id: "owner-1",
      agent_class_name: AsyncAgent.name,
      skill_id: "reply"
    )
  end
end
