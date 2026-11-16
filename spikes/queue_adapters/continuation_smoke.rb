# frozen_string_literal: true

ENV["CONTINUATION_SMOKE"] = "1"
require_relative "support"

worker = nil
log = File.join(SMOKE_ROOT, "continuation-worker.log")
begin
  initialize_smoke_schema!
  store = A2A::Rails.runtime.task_store
  lifecycle = A2A::Rails::Task::Lifecycle.new(store: store, principal_id: "adapter-owner")
  dispatcher = A2A::Rails::Dispatcher.new(agent: QueueAdapterSmoke::Agent,
    configuration: A2A::Rails.configuration)
  handler = A2A::Rails::Protocol::RequestHandler.new(dispatcher: dispatcher, lifecycle: lifecycle)
  send_message = lambda do |id, text, task_id = nil|
    message = { "messageId" => id, "role" => "ROLE_USER", "parts" => [{ "text" => text }] }
    message["taskId"] = task_id if task_id
    handler.call(operation: "SendMessage", params: {
      "message" => message, "historyLength" => 0, "configuration" => { "returnImmediately" => true }
    }).fetch("task")
  end
  task = send_message.call("initial", "begin")
  id = task.fetch("id")
  QueueAdapterSmoke.assert(task.dig("status", "state") == "TASK_STATE_SUBMITTED", "initial async Task not submitted")
  worker = QueueAdapterSmoke.start_worker(log)
  QueueAdapterSmoke.wait_until("first question") { lifecycle.find(id).dig(:status, :state) == :input_required }
  first_turn = lifecycle.find(id).dig(:execution, :turn_id)
  QueueAdapterSmoke.stop_worker(worker)
  worker = nil

  # Close the producer's database connection and reconstruct its lifecycle;
  # the waiting Task must survive both producer reconnection and worker restart.
  ActiveRecord::Base.connection_pool.disconnect!
  lifecycle = A2A::Rails::Task::Lifecycle.new(
    store: A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: "adapter-smoke-cursor-secret".ljust(64, "x")),
    principal_id: "adapter-owner")
  handler = A2A::Rails::Protocol::RequestHandler.new(dispatcher: dispatcher, lifecycle: lifecycle)
  waiting = lifecycle.find(id)
  QueueAdapterSmoke.assert(waiting.dig(:status, :state) == :input_required, "persisted question lost")
  second = send_message.call("answer-1", "incomplete", id)
  QueueAdapterSmoke.assert(second.fetch("id") == id, "resume created another Task")
  second_turn = lifecycle.find(id).dig(:execution, :turn_id)
  QueueAdapterSmoke.assert(first_turn != second_turn, "resume reused execution turn")
  stale = { task_id: id, principal_id: "adapter-owner", agent_class_name: QueueAdapterSmoke::Agent.name,
    skill_id: "reply", turn_id: first_turn }
  A2A::Rails::TaskExecutionJob.perform_later(**stale)
  A2A::Rails::TaskExecutionJob.perform_later(**stale.merge(turn_id: second_turn))
  worker = QueueAdapterSmoke.start_worker(log)
  QueueAdapterSmoke.wait_until("second question") { lifecycle.find(id).dig(:status, :state) == :input_required }
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: id).count == 2, "duplicate or stale Job executed")
  final_submission = send_message.call("answer-2", "123", id)
  QueueAdapterSmoke.assert(final_submission.fetch("id") == id, "final resume created another Task")
  QueueAdapterSmoke.wait_until("same Task completed") { lifecycle.find(id).dig(:status, :state) == :completed }
  final = lifecycle.find(id)
  QueueAdapterSmoke.assert(final.dig(:artifacts, 0, :parts, 0, :data) == { "count" => 3, "total" => 35_000 },
    "wrong result or data key conversion")
  send_message.call("answer-2", "123", id)
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: id).count == 3, "answer replay executed twice")
  QueueAdapterSmoke.assert(final.fetch(:history).length == 5, "questions or user messages lost/duplicated")
  QueueAdapterSmoke::Invocation.where(task_id: id).each do |invocation|
    QueueAdapterSmoke.assert(invocation.idempotency_key == id, "Task idempotency key changed between turns")
  end
  puts "Queue continuation #{ADAPTER}: PASS (separate worker; durable restart; same Task; two questions; old and duplicate Jobs; answer replay)"
rescue StandardError
  warn File.read(log) if File.exist?(log)
  raise
ensure
  QueueAdapterSmoke.stop_worker(worker)
  FileUtils.remove_entry(SMOKE_ROOT) if File.directory?(SMOKE_ROOT)
end
