# frozen_string_literal: true

require_relative "../test_helper"

class TaskLifecycleTest < Minitest::Test
  LoggerDouble = Struct.new(:messages) do
    def error(message)
      messages << message
    end
  end

  def setup
    @store = A2A::Rails::Task::MemoryStore.new
    artifact_mapper = A2A::Rails::Task::ArtifactMapper.new(id_generator: -> { "artifact-1" })
    result_mapper = A2A::Rails::Task::ResultMapper.new(artifact_mapper: artifact_mapper)
    @logger = LoggerDouble.new([])
    @ids = %w[task-1 context-generated task-2 context-generated-2]
    @lifecycle = A2A::Rails::Task::Lifecycle.new(
      store: @store,
      result_mapper: result_mapper,
      logger: @logger,
      clock: -> { Time.utc(2026, 10, 6, 9, 30) },
      id_generator: -> { @ids.shift }
    )
  end

  def input_message
    { message_id: "message-1", role: :user, parts: [{ text: "Hello" }] }
  end

  def test_create_start_and_complete
    submitted = @lifecycle.create(message: input_message, context_id: "context-1")
    assert_equal "task-1", submitted[:id]
    assert_equal "context-1", submitted[:context_id]
    assert_equal :submitted, submitted.dig(:status, :state)

    working = @lifecycle.start(submitted[:id])
    assert_equal :working, working.dig(:status, :state)

    completed = @lifecycle.complete(submitted[:id], "done")
    assert_equal :completed, completed.dig(:status, :state)
    assert_equal "done", completed.dig(:artifacts, 0, :parts, 0, :text)
    assert_equal input_message, completed[:history].first
  end

  def test_missing_context_id_is_generated
    submitted = @lifecycle.create(message: input_message)

    assert_equal "task-1", submitted[:id]
    assert_equal "context-generated", submitted[:context_id]
  end

  def test_reject_preserves_safe_business_reason
    submitted = @lifecycle.create(message: input_message, context_id: "context-1")
    @lifecycle.start(submitted[:id])

    rejected = @lifecycle.reject(submitted[:id], A2A::Rails::RejectedTask.new("Request is not allowed"))

    assert_equal :rejected, rejected.dig(:status, :state)
    assert_equal "Request is not allowed", rejected.dig(:status, :message)
  end

  def test_fail_exposes_generic_message_and_logs_exception_detail
    submitted = @lifecycle.create(message: input_message, context_id: "context-1")
    @lifecycle.start(submitted[:id])
    error = RuntimeError.new("database exploded")

    failed = @lifecycle.fail(submitted[:id], error)

    assert_equal :failed, failed.dig(:status, :state)
    assert_equal "Task execution failed", failed.dig(:status, :message)
    refute_includes failed.dig(:status, :message), "database"
    assert @logger.messages.any? { |entry| entry.include?("RuntimeError") }
    refute @logger.messages.any? { |entry| entry.include?("database exploded") }
  end

  def test_cancel_is_not_overwritten_by_late_completion
    submitted = @lifecycle.create(message: input_message, context_id: "context-1")
    @lifecycle.start(submitted[:id])

    canceled = @lifecycle.cancel(submitted[:id])
    late = @lifecycle.complete(submitted[:id], "late result")

    assert_equal :canceled, canceled.dig(:status, :state)
    assert_equal canceled, late
    refute late.key?(:artifacts)
  end

  def test_list_and_find_delegate_to_store
    submitted = @lifecycle.create(message: input_message, context_id: "context-1")

    assert_equal submitted, @lifecycle.find(submitted[:id])
    assert_equal [submitted[:id]], @lifecycle.list[:tasks].map { |task| task[:id] }
  end
end
