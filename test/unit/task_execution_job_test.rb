# frozen_string_literal: true

require_relative "../test_helper"

class TaskExecutionJobTest < Minitest::Test
  class Handler
    class << self
      attr_accessor :calls
    end

    def self.call(message:, context:)
      self.calls ||= []
      calls << [message, context]
      "job result"
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

  def test_duplicate_delivery_does_not_execute_handler_twice
    perform_task
    perform_task

    assert_equal 1, Handler.calls.length
    assert_equal :completed, @lifecycle.find(@task.fetch(:id)).dig(:status, :state)
  end

  def test_canceled_submitted_task_does_not_start_handler
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
