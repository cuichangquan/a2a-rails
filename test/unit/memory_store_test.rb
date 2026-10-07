# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/task_store_contract"

class MemoryStoreTest < Minitest::Test
  include TaskStoreContract

  def build_contract_store
    A2A::Rails::Task::MemoryStore.new
  end

  def setup
    @store = A2A::Rails::Task::MemoryStore.new
  end

  def task(id, state: :working, timestamp: "2026-10-06T00:00:00.000000Z", context_id: "context-1")
    {
      id: id,
      context_id: context_id,
      status: { state: state, timestamp: timestamp },
      history: [{ message_id: "message-#{id}" }],
      artifacts: [{ artifact_id: "artifact-#{id}", parts: [{ text: id }] }]
    }
  end

  def test_save_and_find_return_isolated_copies
    original = task("task-1")
    @store.save(original)

    original[:status][:state] = :failed
    found = @store.find("task-1")
    found[:history].clear

    assert_equal :working, @store.find("task-1").dig(:status, :state)
    assert_equal 1, @store.find("task-1")[:history].length
  end

  def test_find_unknown_task_raises
    error = assert_raises(A2A::Rails::TaskNotFoundError) { @store.find("missing") }

    assert_equal "missing", error.task_id
  end

  def test_terminal_transition_is_not_overwritten
    @store.save(task("task-1"))
    completed = @store.transition(
      "task-1",
      state: :completed,
      timestamp: Time.utc(2026, 10, 6, 1),
      artifacts: [{ artifact_id: "result", parts: [{ text: "done" }] }]
    )
    unchanged = @store.transition(
      "task-1",
      state: :failed,
      timestamp: Time.utc(2026, 10, 6, 2),
      message: "too late"
    )

    assert_equal :completed, completed.dig(:status, :state)
    assert_equal completed, unchanged
  end

  def test_cancel_is_atomic_and_terminal_states_are_rejected
    @store.save(task("working"))
    canceled = @store.cancel("working", timestamp: Time.utc(2026, 10, 6, 1))

    assert_equal :canceled, canceled.dig(:status, :state)

    A2A::Rails::Task::TERMINAL_STATES.each do |state|
      @store.save(task(state.to_s, state: state))
      error = assert_raises(A2A::Rails::TaskNotCancelableError) { @store.cancel(state.to_s) }
      assert_equal state, error.state
    end
  end

  def test_list_filters_and_uses_stable_snapshot_cursor
    @store.save(task("old", timestamp: "2026-10-06T00:00:00.000000Z"))
    @store.save(task("new", timestamp: "2026-10-06T01:00:00.000000Z"))
    @store.save(task("other", context_id: "other"))

    first = @store.list(context_id: "context-1", status: :working, page_size: 1)
    assert_equal ["new"], first[:tasks].map { |row| row[:id] }
    assert_equal 2, first[:total_size]
    refute_empty first[:next_page_token]

    @store.save(task("newer", timestamp: "2026-10-06T02:00:00.000000Z"))
    second = @store.list(
      context_id: "context-1",
      status: :working,
      page_size: 1,
      page_token: first[:next_page_token]
    )

    assert_equal ["old"], second[:tasks].map { |row| row[:id] }
    assert_equal 2, second[:total_size]
    assert_equal "", second[:next_page_token]
  end

  def test_timestamp_filter_is_inclusive
    @store.save(task("old", timestamp: "2026-10-06T00:00:00.000000Z"))
    @store.save(task("boundary", timestamp: "2026-10-06T01:00:00.000000Z"))

    result = @store.list(status_timestamp_after: "2026-10-06T01:00:00Z")

    assert_equal ["boundary"], result[:tasks].map { |row| row[:id] }
  end

  def test_list_rejects_invalid_page_size_timestamp_and_changed_cursor_query
    [0, 101, "bad"].each do |page_size|
      assert_raises(A2A::Rails::InvalidTaskQueryError) { @store.list(page_size: page_size) }
    end

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(status_timestamp_after: "not-a-time")
    end

    @store.save(task("one"))
    @store.save(task("two", timestamp: "2026-10-06T01:00:00.000000Z"))
    token = @store.list(page_size: 1)[:next_page_token]

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(page_size: 1, context_id: "changed", page_token: token)
    end
  end
  def test_page_token_requires_string
    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(page_token: 123)
    end
  end

  def test_page_snapshots_are_capped_to_avoid_unbounded_memory_growth
    @store.save(task("old", timestamp: "2026-10-06T00:00:00.000000Z"))
    @store.save(task("new", timestamp: "2026-10-06T01:00:00.000000Z"))

    first_token = @store.list(page_size: 1).fetch(:next_page_token)
    (A2A::Rails::Task::MemoryStore::MAX_CACHED_PAGES).times do
      @store.list(page_size: 1)
    end

    assert_operator @store.instance_variable_get(:@pages).size,
      :<=, A2A::Rails::Task::MemoryStore::MAX_CACHED_PAGES
    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(page_size: 1, page_token: first_token)
    end
  end
end
