# frozen_string_literal: true

require "tmpdir"
require "json"
require "fileutils"
require "rbconfig"
require "timeout"

ENV["RAILS_ENV"] = "test"
SMOKE_ROOT = Dir.mktmpdir("a2a-queue-adapter-")
root = SMOKE_ROOT
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


def initialize_smoke_schema!
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

end
