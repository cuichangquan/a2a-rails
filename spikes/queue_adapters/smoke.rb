# frozen_string_literal: true

require "tmpdir"
require "json"
require "fileutils"
require "rbconfig"
require "timeout"

ENV["RAILS_ENV"] = "test"
root = Dir.mktmpdir("a2a-queue-adapter-")
ENV["SMOKE_ROOT"] = root
FileUtils.mkdir_p(File.join(root, "config"))
File.write(File.join(root, "config/database.yml"), <<~YAML)
  test:
    adapter: sqlite3
    database: #{File.join(root, 'smoke.sqlite3')}
    pool: 10
    timeout: 5000
YAML

require_relative "boot"

module QueueAdapterSmoke
  module_function

  def assert(condition, message)
    raise message unless condition
  end

  def wait_until(description)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
    until yield
      raise "Timed out: #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.1
    end
  end

  def start_worker(log)
    command = if ADAPTER == "solid_queue"
      [RbConfig.ruby, File.join(__dir__, "worker.rb")]
    else
      ["bundle", "exec", "sidekiq", "-r", File.join(__dir__, "boot.rb"), "-q", "default", "-c", "2", "-t", "5"]
    end
    Process.spawn(*command, out: log, err: log, pgroup: true)
  end

  def stop_worker(pid)
    return unless pid
    Process.kill("TERM", -pid)
    Timeout.timeout(10) { Process.wait(pid) }
  rescue Timeout::Error
    Process.kill("KILL", -pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def create_task(lifecycle, text)
    lifecycle.create(message: { message_id: "message-#{text}", role: :user,
      parts: [{ text: text }], metadata: {} }, context_id: "adapter-context")
  end

  def enqueue(task)
    job = A2A::Rails::TaskExecutionJob.perform_later(
      task_id: task.fetch(:id), principal_id: "adapter-owner",
      agent_class_name: Agent.name, skill_id: "reply"
    )
    assert(job && job.successfully_enqueued?, "adapter enqueue failed")
    job
  end
end

worker = nil
log = File.join(root, "worker.log")
begin
  ActiveRecord::Schema.verbose = false
  ActiveRecord::Schema.define do
    create_table :a2a_rails_tasks do |t|
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
    create_table :smoke_invocations do |t|
      # Deliberately no uniqueness constraint: a duplicate Handler call must
      # remain observable rather than being hidden by test business logic.
      t.string :task_id, null: false
      t.string :principal_id, null: false
      t.string :idempotency_key, null: false
    end
  end
  if ADAPTER == "solid_queue"
    load File.join(Gem.loaded_specs.fetch("solid_queue").full_gem_path,
      "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
  end

  lifecycle = A2A::Rails::Task::Lifecycle.new(store: A2A::Rails.runtime.task_store,
    principal_id: "adapter-owner")
  tasks = %w[success fail reject cancel].to_h do |text|
    [text, QueueAdapterSmoke.create_task(lifecycle, text)]
  end
  tasks.values.each { |task| QueueAdapterSmoke.enqueue(task) }
  QueueAdapterSmoke.enqueue(tasks.fetch("success"))
  lifecycle.cancel(tasks.fetch("cancel").fetch(:id))

  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.count.zero?, "Handler ran before worker start")
  QueueAdapterSmoke.assert(lifecycle.find(tasks.fetch("success").fetch(:id)).dig(:status, :state) == :submitted,
    "queued Task was not SUBMITTED")
  QueueAdapterSmoke.assert(A2A::Rails::TaskExecutionJob.queue_adapter.class.name.end_with?(ADAPTER == "solid_queue" ? "SolidQueueAdapter" : "SidekiqAdapter"),
    "Task Job did not inherit host queue adapter")

  # Inspect actual backend payloads, then let the real worker consume them.
  payloads = if ADAPTER == "solid_queue"
    SolidQueue::Job.all.map(&:arguments)
  else
    require "sidekiq/api"
    Sidekiq::Queue.new("default").map { |job| job.args.first }
  end
  QueueAdapterSmoke.assert(payloads.length == 5, "unexpected queued payload count")
  payloads.each do |payload|
    arguments = ActiveJob::Arguments.deserialize(payload.fetch("arguments")).first
    QueueAdapterSmoke.assert(arguments.keys.sort == %i[agent_class_name principal_id skill_id task_id].sort,
      "queue contains unexpected application arguments")
    QueueAdapterSmoke.assert(arguments.fetch(:principal_id) == "adapter-owner", "principal changed in queue")
  end

  worker = QueueAdapterSmoke.start_worker(log)
  expected = { "success" => :completed, "fail" => :failed, "reject" => :rejected, "cancel" => :canceled }
  QueueAdapterSmoke.wait_until("Task outcomes") do
    expected.all? { |text, state| lifecycle.find(tasks.fetch(text).fetch(:id)).dig(:status, :state) == state }
  end
  QueueAdapterSmoke.wait_until("queue drained including duplicate/canceled delivery") do
    if ADAPTER == "solid_queue"
      SolidQueue::Job.where(finished_at: nil).count.zero?
    else
      Sidekiq::Queue.new("default").size.zero? && Sidekiq::Workers.new.size.zero?
    end
  end
  expected.each do |text, _|
    calls = QueueAdapterSmoke::Invocation.where(task_id: tasks.fetch(text).fetch(:id))
    QueueAdapterSmoke.assert(calls.count == (text == "cancel" ? 0 : 1), "unexpected Handler count for #{text}")
    calls.each { |call| QueueAdapterSmoke.assert(call.idempotency_key == call.task_id && call.principal_id == "adapter-owner", "Handler context changed") }
  end
  if ADAPTER == "sidekiq"
    QueueAdapterSmoke.assert(Sidekiq::RetrySet.new.size.zero?, "handled Handler errors reached Sidekiq retry set")
  else
    QueueAdapterSmoke.assert(SolidQueue::FailedExecution.count.zero?, "handled Handler errors reached Solid Queue failures")
  end

  QueueAdapterSmoke.stop_worker(worker)
  worker = nil
  restarted = QueueAdapterSmoke.create_task(lifecycle, "restart")
  QueueAdapterSmoke.enqueue(restarted)
  QueueAdapterSmoke.assert(lifecycle.find(restarted.fetch(:id)).dig(:status, :state) == :submitted, "stopped-worker Task not SUBMITTED")
  worker = QueueAdapterSmoke.start_worker(log)
  QueueAdapterSmoke.wait_until("queued Task after worker restart") do
    lifecycle.find(restarted.fetch(:id)).dig(:status, :state) == :completed
  end
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: restarted.fetch(:id)).count == 1,
    "restart Task did not run exactly once in smoke")
  puts "Queue adapter #{ADAPTER}: PASS (real worker, payload, outcomes, duplicate, cancel, restart)"
  puts "Versions: Rails #{Rails.version}; #{ADAPTER} #{Gem.loaded_specs.fetch(ADAPTER).version}"
rescue StandardError
  warn File.read(log) if File.exist?(log)
  raise
ensure
  QueueAdapterSmoke.stop_worker(worker)
  FileUtils.remove_entry(root) if File.directory?(root)
end
