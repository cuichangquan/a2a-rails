# frozen_string_literal: true
require_relative "../test_helper"
require_relative "../support/task_continuation_store_contract"

class TaskContinuationMemoryStoreTest < Minitest::Test
  include TaskContinuationStoreContract

  def build_continuation_store(**options)
    A2A::Rails::Task::MemoryStore.new(**options)
  end

  def test_concurrent_replies_have_one_winner_without_sleep
    store = build_continuation_store
    waiting_task(store)
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do |i|
      Thread.new do
        ready << true
        start.pop
        begin
          store.resume("continuation-task", message: continuation_message("reply-#{i}"), turn_id: "turn-#{i + 2}", principal_id: "owner")[:accepted]
        rescue A2A::Rails::TaskNotResumableError
          false
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [false, true], threads.map(&:value).sort_by { |v| v ? 1 : 0 }
    assert_equal 3, store.find("continuation-task", principal_id: "owner")[:history].size
  end
end
