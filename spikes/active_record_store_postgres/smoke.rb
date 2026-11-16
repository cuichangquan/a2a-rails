# frozen_string_literal: true

require "active_record"
require "timeout"
require "a2a-rails"
require "a2a/rails/task/active_record_store"

DATABASE_URL = ENV.fetch("DATABASE_URL")
SECRET = "step-21-postgres-store-secret".ljust(64, "x")
OWNER = "tenant-A:postgres-smoke"

def assert(condition, message)
  raise message unless condition
end

def connect!
  ActiveRecord::Base.establish_connection(DATABASE_URL)
  ActiveRecord::Base.connection
end

def reset_schema!
  connection = ActiveRecord::Base.connection
  connection.drop_table(:a2a_rails_tasks, if_exists: true)
  connection.create_table(:a2a_rails_tasks) do |t|
    t.string :task_id, null: false
    t.string :owner_id
    t.string :context_id, null: false
    t.string :state, null: false
    t.datetime :status_timestamp, precision: 6, null: false
    t.json :status_message
    t.json :execution
    t.json :history
    t.json :artifacts
    t.datetime :expires_at, precision: 6
    t.timestamps
  end
  connection.add_index :a2a_rails_tasks, :task_id, unique: true
  connection.add_index :a2a_rails_tasks, [:owner_id, :task_id]
  connection.add_index :a2a_rails_tasks, [:owner_id, :context_id, :status_timestamp]
  connection.add_index :a2a_rails_tasks, [:owner_id, :state, :status_timestamp]
  connection.add_index :a2a_rails_tasks, [:owner_id, :status_timestamp]
  connection.add_index :a2a_rails_tasks, :expires_at
end

def task(id, state: :working, timestamp: Time.now.utc.iso8601(6))
  {
    id: id,
    owner_id: OWNER,
    context_id: "postgres-context",
    status: { state: state, timestamp: timestamp },
    history: [{ message_id: "message-#{id}", role: :user, parts: [{ text: id }] }]
  }
end

connect!
reset_schema!

store_a = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET, retention: 60)
store_b = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET, retention: 60)

store_a.save(task("persisted"))
assert(
  store_b.find("persisted", principal_id: OWNER)[:id] == "persisted",
  "second Store instance could not read persisted Task"
)

begin
  store_b.find("persisted", principal_id: "tenant-B:postgres-smoke")
  raise "foreign principal read persisted Task"
rescue A2A::Rails::TaskNotFoundError
  # Expected: foreign and missing are indistinguishable.
end

pid = fork do
  begin
    ActiveRecord::Base.connection_pool.disconnect!
    connect!
    child_store = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET, retention: 60)
    found = child_store.find("persisted", principal_id: OWNER)
    exit!(found[:id] == "persisted" ? 0 : 1)
  rescue StandardError => error
    warn "child process verification failed: #{error.class}: #{error.message}"
    exit! 1
  end
end
_, child_status = Process.wait2(pid)
assert(child_status.success?, "separate process could not read persisted Task")

store_a.save(task("race"))
ready = Queue.new
go = Queue.new
states = %i[completed failed]

threads = states.map do |target_state|
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      local_store = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET, retention: 60)
      ready << true
      go.pop
      local_store.transition(
        "race",
        state: target_state,
        timestamp: Time.now.utc,
        principal_id: OWNER
      ).dig(:status, :state)
    end
  end
end

states.length.times { ready.pop }
states.length.times { go << true }
observed_states = threads.map(&:value)
final_state = store_a.find("race", principal_id: OWNER).dig(:status, :state)

assert(
  A2A::Rails::Task::TERMINAL_STATES.include?(final_state),
  "concurrent transition did not produce terminal state"
)
assert(
  observed_states.all? { |state| state == final_state },
  "row locking allowed conflicting terminal observations: #{observed_states.inspect} final=#{final_state.inspect}"
)

listed = store_b.list(page_size: 10, principal_id: OWNER)
assert(
  listed[:tasks].map { |row| row[:id] }.sort == %w[persisted race],
  "second Store instance did not list shared Tasks"
)

# Two independent worker processes contend for the same SUBMITTED Task.
# Pipes provide a readiness barrier; no timing sleeps decide the winner.
store_a.save(task("duplicate-claim", state: :submitted))
workers = []
begin
  2.times do
    ready_reader, ready_writer = IO.pipe
    go_reader, go_writer = IO.pipe
    result_reader, result_writer = IO.pipe
    pid = fork do
      begin
        ready_reader.close
        go_writer.close
        result_reader.close
        ActiveRecord::Base.connection_pool.disconnect!
        connect!
        worker_store = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET)
        ready_writer.puts "ready"
        ready_writer.close
        go_reader.gets
        claimed = worker_store.claim_execution("duplicate-claim", principal_id: OWNER)
        result_writer.puts(claimed ? "won" : "duplicate")
        result_writer.close
        exit! 0
      rescue StandardError => error
        warn "claim worker failed: #{error.class}"
        exit! 1
      end
    end
    ready_writer.close
    go_reader.close
    result_writer.close
    workers << [pid, ready_reader, go_writer, result_reader]
  end

  outcomes = Timeout.timeout(15) do
    workers.each { |_, ready, _, _| assert(ready.gets == "ready\n", "claim worker not ready") }
    workers.each { |_, _, go_pipe, _| go_pipe.puts "go"; go_pipe.close }
    workers.map do |worker|
      pid, _, _, result = worker
      outcome = result.gets&.strip
      _, status = Process.wait2(pid)
      worker[0] = nil
      assert(status.success?, "claim worker failed")
      outcome
    end
  end
  assert(outcomes.sort == %w[duplicate won], "duplicate workers both claimed: #{outcomes.inspect}")
  assert(store_b.find("duplicate-claim", principal_id: OWNER).dig(:status, :state) == :working,
    "claimed Task did not remain WORKING")
  assert(store_b.claim_execution("duplicate-claim", principal_id: OWNER).nil?,
    "ambiguous WORKING Task was claimed again")
ensure
  workers.each do |pid, *pipes|
    pipes.each { |pipe| pipe.close unless pipe.closed? }
    next unless pid
    begin
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # Already reaped after successful completion.
    end
  end
end

puts "Cross-process duplicate execution claim: PASS (one winner)"
puts "ActiveRecord Task Store PostgreSQL smoke: PASS"
puts "Final concurrent terminal state: #{final_state}"

# Continuation uses the same row lock as cancellation, not a process-local lock.
def waiting_continuation(store, id)
  store.save(task(id, state: :submitted))
  store.configure_execution(id, principal_id: OWNER, execution: {
    agent_class_name: "ExampleAgent", skill_id: "report", execution_mode: :async,
    turn_id: "initial", message_id: "message-#{id}"
  })
  store.claim_execution(id, turn_id: "initial", principal_id: OWNER)
  store.transition(id, state: :input_required, turn_id: "initial", principal_id: OWNER,
    message: { message_id: "question", role: :agent, parts: [{ text: "Department?" }] })
end

def reply_message(id)
  { message_id: id, role: :user, parts: [{ data: { "department_id" => 123,
    "messageId" => false, "message_id" => nil, "nested" => [{}, []] }, media_type: "application/json" }], metadata: {} }
end

def simultaneous_processes(count, &operation)
  workers = []
  count.times do |i|
    ready_r, ready_w = IO.pipe
    go_r, go_w = IO.pipe
    result_r, result_w = IO.pipe
    pid = fork do
      ready_r.close; go_w.close; result_r.close
      begin
        ActiveRecord::Base.connection_pool.disconnect!
        connect!
        child_store = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: SECRET)
        ready_w.puts "ready"
        ready_w.close
        go_r.gets
        result_w.puts(operation.call(child_store, i))
        result_w.close
        exit! 0
      rescue StandardError => error
        warn "continuation process failed: #{error.class}"
        exit! 1
      end
    end
    ready_w.close; go_r.close; result_w.close
    workers << [pid, ready_r, go_w, result_r]
  end
  Timeout.timeout(20) do
    workers.each { |_, ready, _, _| assert(ready.gets == "ready\n", "continuation worker not ready") }
    workers.each { |_, _, go, _| go.puts "go"; go.close }
    workers.map do |worker|
      pid, _, _, result = worker
      output = result.gets&.strip
      _, status = Process.wait2(pid)
      worker[0] = nil
      assert(status.success?, "continuation worker failed")
      output
    end
  end
ensure
  workers.each do |pid, *pipes|
    pipes.each { |pipe| pipe.close unless pipe.closed? }
    next unless pid
    begin
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end

waiting_continuation(store_a, "two-answers")
outcomes = simultaneous_processes(2) do |store, i|
  begin
    result = store.resume("two-answers", message: reply_message("reply-#{i}"), turn_id: "turn-#{i}", principal_id: OWNER)
    result[:accepted] ? "accepted" : "duplicate"
  rescue A2A::Rails::TaskNotResumableError
    "rejected"
  end
end
assert(outcomes.sort == %w[accepted rejected], "two answers both won: #{outcomes.inspect}")
assert(store_b.find("two-answers", principal_id: OWNER)[:history].length == 3, "duplicate history appended")

waiting_continuation(store_a, "same-answer")
outcomes = simultaneous_processes(2) do |store, i|
  store.resume("same-answer", message: reply_message("same"), turn_id: "turn-#{i}", principal_id: OWNER)[:accepted] ? "accepted" : "duplicate"
end
assert(outcomes.sort == %w[accepted duplicate], "same answer dedupe failed: #{outcomes.inspect}")

waiting_continuation(store_a, "answer-cancel")
outcomes = simultaneous_processes(2) do |store, i|
  if i.zero?
    begin
      store.resume("answer-cancel", message: reply_message("reply"), turn_id: "second", principal_id: OWNER)
      "accepted"
    rescue A2A::Rails::TaskNotResumableError
      "rejected"
    end
  else
    store.cancel("answer-cancel", principal_id: OWNER)
    "canceled"
  end
end
assert(outcomes.include?("canceled"), "cancel failed")
assert(store_a.find("answer-cancel", principal_id: OWNER).dig(:status, :state) == :canceled, "answer revived canceled Task")
assert(store_a.claim_execution("answer-cancel", turn_id: "second", principal_id: OWNER).nil?, "canceled Task was claimed")

waiting_continuation(store_a, "restart-resume")
outcomes = simultaneous_processes(1) do |store, _|
  resumed = store.resume("restart-resume", message: reply_message("restarted-reply"), turn_id: "after-restart", principal_id: OWNER)
  assert(resumed[:task].dig(:history, 2, :parts, 0, :data) == reply_message("x")[:parts][0][:data], "restart changed Data keys")
  claimed = store.claim_execution("restart-resume", turn_id: "after-restart", principal_id: OWNER)
  assert(claimed, "restart did not claim")
  store.transition("restart-resume", state: :completed, turn_id: "after-restart", principal_id: OWNER)
  "completed"
end
assert(outcomes == ["completed"], "restart resume did not complete")
assert(store_a.find("restart-resume", principal_id: OWNER).dig(:status, :state) == :completed, "completion was not durable")
puts "PostgreSQL continuation: PASS (cross-process distinct replies, duplicate reply, cancellation, restart)"
