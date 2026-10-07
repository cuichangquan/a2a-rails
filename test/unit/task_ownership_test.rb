# frozen_string_literal: true

require_relative "../test_helper"

class TaskOwnershipTest < Minitest::Test
  def setup
    @store = A2A::Rails::Task::MemoryStore.new
    @alice = A2A::Rails::Task::Lifecycle.new(store: @store, principal_id: "alice")
    @bob = A2A::Rails::Task::Lifecycle.new(store: @store, principal_id: "bob")
    @anonymous = A2A::Rails::Task::Lifecycle.new(store: @store)
  end

  def input_message
    { message_id: "m1", role: :user, parts: [{ text: "private" }], metadata: {} }
  end

  def test_find_and_cancel_hide_foreign_and_anonymous_tasks
    a = @alice.create(message: input_message, context_id: "shared-context")
    b = @bob.create(message: input_message, context_id: "shared-context")
    u = @anonymous.create(message: input_message, context_id: "shared-context")

    assert_equal a[:id], @alice.find(a[:id])[:id]
    assert_equal b[:id], @bob.find(b[:id])[:id]
    assert_raises(A2A::Rails::TaskNotFoundError) { @alice.find(b[:id]) }
    assert_raises(A2A::Rails::TaskNotFoundError) { @bob.find(a[:id]) }
    assert_raises(A2A::Rails::TaskNotFoundError) { @alice.find(u[:id]) }
    assert_raises(A2A::Rails::TaskNotFoundError) { @anonymous.find(a[:id]) }
    assert_raises(A2A::Rails::TaskNotFoundError) { @bob.cancel(a[:id]) }

    assert_equal :submitted, @alice.find(a[:id]).dig(:status, :state)
    assert_equal :canceled, @alice.cancel(a[:id]).dig(:status, :state)
  end

  def test_list_is_scoped_before_filter_count_and_pagination
    a1 = @alice.create(message: input_message, context_id: "shared-context")
    a2 = @alice.create(message: input_message, context_id: "shared-context")
    b = @bob.create(message: input_message, context_id: "shared-context")
    u = @anonymous.create(message: input_message, context_id: "shared-context")

    first = @alice.list(page_size: 1)
    assert_equal 2, first.fetch(:total_size)
    assert_equal 1, first.fetch(:tasks).size
    refute_empty first.fetch(:next_page_token)

    second = @alice.list(page_size: 1, page_token: first.fetch(:next_page_token))
    assert_equal [a1[:id], a2[:id]].sort, (first[:tasks] + second[:tasks]).map { |x| x[:id] }.sort
    assert_equal 2, second.fetch(:total_size)
    assert_equal "", second.fetch(:next_page_token)

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @bob.list(page_size: 1, page_token: first[:next_page_token])
    end
    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      @anonymous.list(page_size: 1, page_token: first[:next_page_token])
    end

    assert_equal [b[:id]], @bob.list(context_id: "shared-context")[:tasks].map { |x| x[:id] }
    assert_equal [u[:id]], @anonymous.list[:tasks].map { |x| x[:id] }
    assert_equal 1, @bob.list[:total_size]
    assert_equal 1, @anonymous.list[:total_size]
    assert_equal 0, @bob.list(context_id: "missing")[:total_size]
  end

  def test_transitions_are_scoped_and_atomic_even_during_races
    a = @alice.create(message: input_message)
    @alice.start(a[:id])
    assert_raises(A2A::Rails::TaskNotFoundError) { @bob.complete(a[:id], "intrusion") }
    assert_raises(A2A::Rails::TaskNotFoundError) { @bob.start(a[:id]) }
    assert_raises(A2A::Rails::TaskNotFoundError) { @bob.reject(a[:id], A2A::Rails::RejectedTask.new("bad")) }

    @alice.cancel(a[:id])
    completed = @alice.complete(a[:id], "late")
    assert_equal :canceled, completed.dig(:status, :state)
    refute completed.key?(:artifacts)
  end

  def test_private_owner_is_not_serialized_by_task_mapper
    task = @alice.create(message: input_message)
    assert_equal "alice", task[:owner_id]
    payload = A2A::Rails::Protocol::TaskMapper.new.dump(task)
    refute payload.key?("owner_id")
    refute payload.key?("ownerId")
    refute_includes payload.inspect, "alice"
  end
end
