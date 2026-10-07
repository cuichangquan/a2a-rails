# frozen_string_literal: true

require_relative "../test_helper"
require "active_record"
require "sqlite3"
require_relative "../../lib/a2a/rails/task/active_record_store"

ActiveRecord::Schema.verbose = false
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :a2a_rails_tasks, force: true do |t|
    t.string :task_id, null: false
    t.string :owner_id
    t.string :context_id, null: false
    t.string :state, null: false
    t.datetime :status_timestamp, precision: 6, null: false
    t.json :status_message
    t.json :history
    t.json :artifacts
    t.datetime :expires_at, precision: 6
    t.timestamps
  end

  add_index :a2a_rails_tasks, :task_id, unique: true
  add_index :a2a_rails_tasks, [:owner_id, :task_id]
  add_index :a2a_rails_tasks, [:owner_id, :context_id, :status_timestamp]
  add_index :a2a_rails_tasks, [:owner_id, :state, :status_timestamp]
  add_index :a2a_rails_tasks, [:owner_id, :status_timestamp]
  add_index :a2a_rails_tasks, :expires_at
end

class ActiveRecordStoreTest < Minitest::Test
  SECRET = "step-21-active-record-store-test-secret".ljust(64, "x")

  def setup
    A2A::Rails::Task::ActiveRecordStore::Record.delete_all
    @store = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET)
  end

  def task(id, owner_id: "tenant-A:user-1", state: :working,
    timestamp: "2026-10-07T00:00:00.000000Z", context_id: "context-1",
    artifacts: :absent)
    value = {
      id: id,
      owner_id: owner_id,
      context_id: context_id,
      status: { state: state, timestamp: timestamp },
      history: [
        {
          message_id: "message-#{id}",
          role: :user,
          parts: [{ text: id, metadata: { source: "test" } }]
        }
      ]
    }
    value[:artifacts] = artifacts unless artifacts == :absent
    value
  end

  def test_save_and_find_round_trip_without_changing_optional_shape
    saved = @store.save(task("task-1"))

    assert_equal "task-1", saved[:id]
    assert_equal "tenant-A:user-1", saved[:owner_id]
    assert_equal :working, saved.dig(:status, :state)
    assert_equal({ source: "test" }, saved.dig(:history, 0, :parts, 0, :metadata))
    refute saved.key?(:artifacts)

    found = @store.find("task-1", principal_id: "tenant-A:user-1")
    assert_equal saved, found
  end

  def test_new_store_instance_reads_same_database_task
    @store.save(task("persistent"))

    restarted = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET)

    assert_equal "persistent",
      restarted.find("persistent", principal_id: "tenant-A:user-1")[:id]
  end

  def test_owner_isolation_happens_during_lookup
    @store.save(task("private"))

    assert_raises(A2A::Rails::TaskNotFoundError) do
      @store.find("private", principal_id: "tenant-B:user-1")
    end
  end

  def test_transition_is_terminal_idempotent_and_round_trips_artifacts
    @store.save(task("task-1"))

    completed = @store.transition(
      "task-1",
      state: :completed,
      timestamp: Time.utc(2026, 10, 7, 1),
      artifacts: [{ artifact_id: "result", parts: [{ text: "done" }] }],
      principal_id: "tenant-A:user-1"
    )

    unchanged = @store.transition(
      "task-1",
      state: :failed,
      timestamp: Time.utc(2026, 10, 7, 2),
      message: "too late",
      principal_id: "tenant-A:user-1"
    )

    assert_equal :completed, completed.dig(:status, :state)
    assert_equal "done", completed.dig(:artifacts, 0, :parts, 0, :text)
    assert_equal completed, unchanged
  end

  def test_cancel_locks_and_rejects_terminal_task
    @store.save(task("working"))

    canceled = @store.cancel(
      "working",
      timestamp: Time.utc(2026, 10, 7, 1),
      principal_id: "tenant-A:user-1"
    )
    assert_equal :canceled, canceled.dig(:status, :state)

    error = assert_raises(A2A::Rails::TaskNotCancelableError) do
      @store.cancel("working", principal_id: "tenant-A:user-1")
    end
    assert_equal :canceled, error.state
  end

  def test_list_uses_owner_scoped_keyset_cursor_and_excludes_later_inserts
    @store.save(task("old", timestamp: "2026-10-07T00:00:00.000000Z"))
    @store.save(task("new", timestamp: "2026-10-07T01:00:00.000000Z"))
    @store.save(task("foreign", owner_id: "tenant-B:user-1",
      timestamp: "2026-10-07T02:00:00.000000Z"))

    first = @store.list(
      context_id: "context-1",
      status: :working,
      page_size: 1,
      principal_id: "tenant-A:user-1"
    )

    assert_equal ["new"], first[:tasks].map { |row| row[:id] }
    assert_equal 2, first[:total_size]
    refute_empty first[:next_page_token]

    @store.save(task("newer", timestamp: "2026-10-07T03:00:00.000000Z"))

    second = @store.list(
      context_id: "context-1",
      status: :working,
      page_size: 1,
      page_token: first[:next_page_token],
      principal_id: "tenant-A:user-1"
    )

    assert_equal ["old"], second[:tasks].map { |row| row[:id] }
    assert_equal 2, second[:total_size]
    assert_equal "", second[:next_page_token]

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(
        context_id: "context-1",
        status: :working,
        page_size: 1,
        page_token: first[:next_page_token],
        principal_id: "tenant-B:user-1"
      )
    end
  end

  def test_list_rejects_tampered_cursor_and_changed_query
    @store.save(task("old", timestamp: "2026-10-07T00:00:00.000000Z"))
    @store.save(task("new", timestamp: "2026-10-07T01:00:00.000000Z"))
    token = @store.list(page_size: 1, principal_id: "tenant-A:user-1")
      .fetch(:next_page_token)

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(page_size: 1, page_token: "#{token}tampered",
        principal_id: "tenant-A:user-1")
    end

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @store.list(page_size: 1, page_token: token, context_id: "changed",
        principal_id: "tenant-A:user-1")
    end
  end

  def test_timestamp_filter_is_inclusive
    @store.save(task("old", timestamp: "2026-10-07T00:00:00.000000Z"))
    @store.save(task("boundary", timestamp: "2026-10-07T01:00:00.000000Z"))

    result = @store.list(
      status_timestamp_after: "2026-10-07T01:00:00Z",
      principal_id: "tenant-A:user-1"
    )

    assert_equal ["boundary"], result[:tasks].map { |row| row[:id] }
  end
  def test_terminal_tasks_receive_expiry_and_prune_is_bounded
    store = A2A::Rails::Task::ActiveRecordStore.new(
      cursor_secret: SECRET,
      retention: 3_600,
      prune_batch_size: 1
    )
    completed_at = Time.utc(2026, 10, 7, 1)

    store.save(task("one"))
    store.save(task("two"))
    store.transition("one", state: :completed, timestamp: completed_at,
      principal_id: "tenant-A:user-1")
    store.transition("two", state: :failed, timestamp: completed_at,
      principal_id: "tenant-A:user-1")

    records = A2A::Rails::Task::ActiveRecordStore::Record.order(:task_id).to_a
    assert records.all? { |record| record.expires_at == completed_at + 3_600 }

    assert_equal 0, store.prune_expired(at: completed_at + 3_599)
    assert_equal 1, store.prune_expired(at: completed_at + 3_600)
    assert_equal 1, A2A::Rails::Task::ActiveRecordStore::Record.count
    assert_equal 1, store.prune_expired(at: completed_at + 3_600)
    assert_equal 0, A2A::Rails::Task::ActiveRecordStore::Record.count
  end

  def test_cancel_sets_terminal_expiry
    store = A2A::Rails::Task::ActiveRecordStore.new(
      cursor_secret: SECRET,
      retention: 120
    )
    canceled_at = Time.utc(2026, 10, 7, 2)

    store.save(task("cancel-me"))
    store.cancel("cancel-me", timestamp: canceled_at, principal_id: "tenant-A:user-1")

    record = A2A::Rails::Task::ActiveRecordStore::Record.find_by!(task_id: "cancel-me")
    assert_equal canceled_at + 120, record.expires_at
  end

  def test_owner_quota_ignores_expired_rows_even_before_prune
    clock = Time.utc(2026, 10, 7, 3)
    store = A2A::Rails::Task::ActiveRecordStore.new(
      cursor_secret: SECRET,
      clock: -> { clock },
      retention: 10,
      max_tasks_per_owner: 1
    )

    store.save(task("first", timestamp: clock.iso8601(6)))

    assert_raises(A2A::Rails::TaskStoreCapacityError) do
      store.save(task("blocked", timestamp: clock.iso8601(6)))
    end

    store.transition("first", state: :completed, timestamp: clock,
      principal_id: "tenant-A:user-1")
    clock += 11

    saved = store.save(task("second", timestamp: clock.iso8601(6)))
    assert_equal "second", saved[:id]
    assert_equal 2, A2A::Rails::Task::ActiveRecordStore::Record.count
  end

  def test_payload_collection_limits_are_enforced_without_truncation
    store = A2A::Rails::Task::ActiveRecordStore.new(
      cursor_secret: SECRET,
      max_history_entries: 1,
      max_artifacts: 1
    )

    too_much_history = task("history")
    too_much_history[:history] << { message_id: "extra", role: :user, parts: [{ text: "extra" }] }

    assert_raises(A2A::Rails::TaskStorePayloadLimitError) do
      store.save(too_much_history)
    end

    store.save(task("artifacts"))
    assert_raises(A2A::Rails::TaskStorePayloadLimitError) do
      store.transition(
        "artifacts",
        state: :completed,
        artifacts: [
          { artifact_id: "one", parts: [{ text: "one" }] },
          { artifact_id: "two", parts: [{ text: "two" }] }
        ],
        principal_id: "tenant-A:user-1"
      )
    end

    found = store.find("artifacts", principal_id: "tenant-A:user-1")
    assert_equal :working, found.dig(:status, :state)
    refute found.key?(:artifacts)
  end

  def test_maintenance_stats_expose_counts_without_task_content
    now = Time.utc(2026, 10, 7, 4)
    store = A2A::Rails::Task::ActiveRecordStore.new(
      cursor_secret: SECRET,
      retention: 60
    )

    store.save(task("task-active-123", timestamp: now.iso8601(6)))
    store.save(task("task-terminal-456", timestamp: now.iso8601(6)))
    store.transition("task-terminal-456", state: :completed, timestamp: now,
      principal_id: "tenant-A:user-1")

    stats = store.maintenance_stats(at: now + 61)

    assert_equal({ total: 2, terminal: 1, active: 1, expired: 1 }, stats)
    refute_includes stats.to_s, "tenant-A:user-1"
    refute_includes stats.to_s, "task-terminal-456"
  end

end
