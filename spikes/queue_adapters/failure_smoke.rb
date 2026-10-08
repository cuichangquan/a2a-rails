# frozen_string_literal: true

# Step 26-3 failure/recovery contract. Deliberately starts REAL Solid Queue or
# Sidekiq workers with an ActiveRecordStore backed by persistent SQLite.
# This is a source-tree queue contract smoke; installed Gem/PG hosts have their
# own independent evidence. Never run against a production queue or database.
ENV["ASYNC_FAILURE_SMOKE"] = "1"
require_relative "support"
require "open3"
require "securerandom"

module QueueAdapterSmoke
  class BusinessEffect < ActiveRecord::Base
    self.table_name = "smoke_business_effects"
  end

  module_function

  def read_in_fresh_process!(id, expected_state)
    source = File.expand_path("boot.rb", __dir__)
    code = <<~'RUBY'
      require ARGV.fetch(0)
      store = A2A::Rails.runtime.task_store
      task = store.find(ARGV.fetch(1), principal_id: "adapter-owner")
      expected = ARGV.fetch(2).to_sym
      abort "fresh process observed #{task.dig(:status, :state)} not #{expected}" unless
        task.dig(:status, :state) == expected
      puts "Fresh process confirmed #{expected}"
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", code,
      source, id, expected_state.to_s)
    assert(status.success?, "fresh Rails process could not observe persisted Task: #{stderr} #{stdout}")
    puts stdout
  end

  def hard_kill_worker!(pid)
    Process.kill("KILL", -pid)
    Timeout.timeout(10) { Process.wait(pid) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def assert_one_business_effect!(principal:, task_id:)
    effect = { principal_id: principal, idempotency_key: task_id }
    2.times do
      # Host business example: the UNIQUE index, not Task completion alone,
      # rejects repeated writes using the stable Task idempotency key.
      BusinessEffect.insert_all([effect],
        unique_by: "idx_business_effects_owner_key")
    end
    assert(BusinessEffect.where(effect).count == 1,
      "host business idempotency index failed to deduplicate repeated requests")
  end
end

worker = nil
root = SMOKE_ROOT
log = File.join(root, "failure-worker.log")
begin
  initialize_smoke_schema!
  ActiveRecord::Schema.define do
    create_table :smoke_business_effects do |t|
      t.string :principal_id, null: false
      t.string :idempotency_key, null: false
    end
    add_index :smoke_business_effects, [:principal_id, :idempotency_key],
      unique: true, name: "idx_business_effects_owner_key"
  end

  store = A2A::Rails.runtime.task_store
  lifecycle = A2A::Rails::Task::Lifecycle.new(store: store, principal_id: "adapter-owner")

  # Deterministic simulate-a-queue-adapter failure *after* persistent Task
  # commit; no test relies on making Redis/Solid Queue unavailable.
  [
    ["false-return", ->(**) { false }],
    ["exception", ->(**) { raise "private-backend-error-do-not-expose" }]
  ].each do |label, failing_enqueue|
    job_class = Object.new
    job_class.define_singleton_method(:perform_later, &failing_enqueue)
    dispatcher = A2A::Rails::Dispatcher.new(
      agent: QueueAdapterSmoke::Agent, configuration: A2A::Rails.configuration
    )
    handler = A2A::Rails::Protocol::RequestHandler.new(
      dispatcher: dispatcher, lifecycle: lifecycle, task_job: job_class
    )
    output = handler.call(operation: "SendMessage", params: { "message" => {
      "messageId" => SecureRandom.uuid, "role" => "ROLE_USER",
      "parts" => [{ "text" => label }]
    } })
    task = output.fetch("task")
    id = task.fetch("id")
    QueueAdapterSmoke.assert(task.dig("status", "state") == "TASK_STATE_FAILED",
      "synchronous enqueue failure did not mark Task FAILED")
    QueueAdapterSmoke.assert(!JSON.generate(task).include?("private-backend-error"),
      "enqueue adapter credential leaked into Task wire result")
    QueueAdapterSmoke.read_in_fresh_process!(id, :failed)
  end

  # A crash after Task commit but BEFORE enqueue is an unrecoverable gap
  # without a host-owned outbox/reconciliation loop.
  missing_enqueue = QueueAdapterSmoke.create_task(lifecycle, "commit-no-enqueue")
  orphan_id = missing_enqueue.fetch(:id)
  QueueAdapterSmoke.read_in_fresh_process!(orphan_id, :submitted)
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: orphan_id).count.zero?,
    "non-enqueued Task executed unexpectedly")

  # A duplicate that arrives after Cancel must not execute the Handler.
  canceled = QueueAdapterSmoke.create_task(lifecycle, "cancel-before-claim")
  QueueAdapterSmoke.enqueue(canceled)
  lifecycle.cancel(canceled.fetch(:id))
  QueueAdapterSmoke.enqueue(canceled)

  # Crash AFTER atomic claim and BEFORE Handler result commit: the Task
  # stays ambiguous WORKING. A restart or duplicate delivery MUST NOT turn
  # it into a second business execution.
  crashed = QueueAdapterSmoke.create_task(lifecycle, "crash")
  QueueAdapterSmoke.enqueue(crashed)
  worker = QueueAdapterSmoke.start_worker(log)
  QueueAdapterSmoke.wait_until("crash Task claimed and entered Handler") do
    lifecycle.find(crashed.fetch(:id)).dig(:status, :state) == :working &&
      QueueAdapterSmoke::Invocation.where(task_id: crashed.fetch(:id)).count == 1
  end
  QueueAdapterSmoke.hard_kill_worker!(worker)
  worker = nil

  post_crash = lifecycle.find(crashed.fetch(:id))
  QueueAdapterSmoke.assert(post_crash.dig(:status, :state) == :working &&
    !post_crash.key?(:artifacts), "crashed Task unexpectedly got a terminal outcome")
  QueueAdapterSmoke.read_in_fresh_process!(crashed.fetch(:id), :working)
  QueueAdapterSmoke.assert(A2A::Rails.runtime.task_store.claim_execution(
    crashed.fetch(:id), principal_id: "adapter-owner").nil?,
    "ambiguous WORKING Task was automatically reclaimable")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: crashed.fetch(:id)).count == 1,
    "business call duplicated at worker crash")

  # Reconcile SUBMITTED orphan using the *same* task ID; do NOT blindly
  # reset/re-enqueue an ambiguous WORKING task after external side effects.
  QueueAdapterSmoke.enqueue(missing_enqueue)
  duplicate = QueueAdapterSmoke.enqueue(crashed)
  worker = QueueAdapterSmoke.start_worker(log)
  QueueAdapterSmoke.wait_until("reconciled submitted Task completes after restart") do
    lifecycle.find(orphan_id).dig(:status, :state) == :completed
  end
  QueueAdapterSmoke.wait_until("duplicate job delivered by restarted queue worker") do
    if ADAPTER == "solid_queue"
      job = SolidQueue::Job.find_by(active_job_id: duplicate.job_id)
      job && !job.finished_at.nil?
    else
      # Sidekiq jobs are removed from Redis on success. The original crashed
      # job may have been requeued by the backend; the Gem claim is decisive.
      require "sidekiq/api"
      Sidekiq::Queue.new("default").none? { |j| j.item["wrapped"] == "A2A::Rails::TaskExecutionJob" &&
        j.args.first["job_id"] == duplicate.job_id } &&
        Sidekiq::Workers.new.none? { |_pid, _tid, work|
          work.dig("payload", "args", 0, "job_id") == duplicate.job_id
        }
    end
  end
  QueueAdapterSmoke.assert(lifecycle.find(crashed.fetch(:id)).dig(:status, :state) == :working,
    "replayed ambiguous WORKING Task was silently re-executed or finalized")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: crashed.fetch(:id)).count == 1,
    "duplicate worker delivery re-executed crashed Handler")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: orphan_id).count == 1,
    "committed-before-enqueue Task reconciliation invoked Handler multiple times")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: canceled.fetch(:id)).count.zero?,
    "canceled SUBMITTED Task reached Handler")

  # Handler is not allowed to claim exactly-once external effects. A real
  # host must enforce the key at the business data boundary as shown here.
  QueueAdapterSmoke.assert_one_business_effect!(principal: "adapter-owner",
    task_id: crashed.fetch(:id))
  QueueAdapterSmoke.assert_one_business_effect!(principal: "adapter-owner",
    task_id: orphan_id)
  QueueAdapterSmoke.assert(QueueAdapterSmoke::BusinessEffect.count == 2,
    "unrelated Task idempotency keys were incorrectly merged")
  QueueAdapterSmoke.assert(A2A::Rails::TaskExecutionJob.enqueue_after_transaction_commit == false,
    "unexpected enqueue/commit contract change")

  puts "Step 26-3 #{ADAPTER}: PASS (real worker SIGKILL; ambiguous WORKING; duplicate suppressed; " \
    "cancel before work; orphan reconciliation; failed enqueue; business idempotency)"
rescue StandardError
  warn File.read(log) if File.exist?(log)
  raise
ensure
  QueueAdapterSmoke.stop_worker(worker)
  FileUtils.remove_entry(root) if File.directory?(root)
end
