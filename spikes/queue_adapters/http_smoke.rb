# frozen_string_literal: true

ENV["HTTP_ASYNC_SMOKE"] = "1"
require_relative "support"
require "net/http"

module QueueAdapterSmoke
  module_function

  def rpc(method, params = {}, token: "test-a")
    request = Net::HTTP::Post.new("/a2a")
    request["Content-Type"] = "application/json"
    request["A2A-Version"] = "1.0"
    request["Authorization"] = "Bearer #{token}" if token
    request.body = JSON.generate(jsonrpc: "2.0", id: "http-smoke", method: method, params: params)
    http = Net::HTTP.new("127.0.0.1", 9997, nil)
    http.open_timeout = 2
    http.read_timeout = 5
    response = http.request(request)
    [response.code.to_i, JSON.parse(response.body)]
  end

  def result(method, params = {}, token: "test-a")
    status, body = rpc(method, params, token: token)
    assert(status == 200 && !body.key?("error"), "#{method} failed: #{status} #{body}")
    body.fetch("result")
  end

  def send_task(text)
    task = result("SendMessage", { "message" => {
      "messageId" => SecureRandom.uuid, "contextId" => "http-async-context",
      "role" => "ROLE_USER", "parts" => [{ "text" => text }]
    } }).fetch("task")
    assert(task.dig("status", "state") == "TASK_STATE_SUBMITTED", "SendMessage did not return SUBMITTED")
    task.fetch("id")
  end

  def get_task(id)
    result("GetTask", { "id" => id })
  end

  def assert_state(id, state)
    assert(get_task(id).dig("status", "state") == "TASK_STATE_#{state}", "unexpected Task state: #{state}")
    listing = result("ListTasks", { "contextId" => "http-async-context" })
    listed = listing.fetch("tasks").find { |task| task.fetch("id") == id }
    assert(listed && listed.dig("status", "state") == "TASK_STATE_#{state}", "ListTasks did not observe #{state}")
  end

  def start_http(log)
    pid = Process.spawn(RbConfig.ruby, File.join(__dir__, "http_server.rb"), out: log, err: log, pgroup: true)
    begin
      wait_until("HTTP SUT readiness") do
        begin
          http = Net::HTTP.new("127.0.0.1", 9997, nil)
          http.open_timeout = 1
          http.read_timeout = 2
          http.get("/.well-known/agent-card.json").code == "200"
        rescue IOError, SystemCallError, Timeout::Error
          false
        end
      end
    rescue StandardError
      stop_worker(pid)
      raise
    end
    pid
  end

  def release(id)
    File.write(File.join(SMOKE_ROOT, "release-#{id}"), "go")
  end

  def drained?
    if ADAPTER == "solid_queue"
      SolidQueue::Job.where(finished_at: nil).count.zero?
    else
      require "sidekiq/api"
      Sidekiq::Queue.new("default").size.zero? && Sidekiq::Workers.new.size.zero?
    end
  end
end

web = worker = nil
web_log = File.join(SMOKE_ROOT, "http.log")
worker_log = File.join(SMOKE_ROOT, "worker.log")
begin
  initialize_smoke_schema!
  ActiveRecord::Schema.define do
    create_table(:smoke_route_invocations) { |t| t.string :task_id, null: false }
  end
  web = QueueAdapterSmoke.start_http(web_log)
  status, = QueueAdapterSmoke.rpc("SendMessage", {}, token: nil)
  QueueAdapterSmoke.assert(status == 401, "unauthenticated async request allowed")

  id = QueueAdapterSmoke.send_task("hold")
  QueueAdapterSmoke.assert_state(id, "SUBMITTED")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.count.zero?, "HTTP executed Handler inline")
  %w[GetTask CancelTask].each do |method|
    status, body = QueueAdapterSmoke.rpc(method, { "id" => id }, token: "test-b")
    QueueAdapterSmoke.assert(status == 200 && body.dig("error", "code") == -32_001, "foreign owner #{method} allowed")
  end
  foreign = QueueAdapterSmoke.result("ListTasks", {}, token: "test-b")
  QueueAdapterSmoke.assert(foreign.fetch("totalSize") == 0, "foreign owner listed Tasks")

  queued_cancel = QueueAdapterSmoke.send_task("hold")
  QueueAdapterSmoke.result("CancelTask", { "id" => queued_cancel })
  QueueAdapterSmoke.assert_state(queued_cancel, "CANCELED")

  # Restart web with queued work: HTTP process memory cannot be its source of truth.
  QueueAdapterSmoke.stop_worker(web)
  web = nil
  web = QueueAdapterSmoke.start_http(web_log)
  QueueAdapterSmoke.assert_state(id, "SUBMITTED")
  worker = QueueAdapterSmoke.start_worker(worker_log)
  QueueAdapterSmoke.wait_until("HTTP WORKING") do
    QueueAdapterSmoke.get_task(id).dig("status", "state") == "TASK_STATE_WORKING" &&
      QueueAdapterSmoke::Invocation.where(task_id: id).count == 1
  end
  QueueAdapterSmoke.assert_state(id, "WORKING")
  QueueAdapterSmoke.release(id)
  QueueAdapterSmoke.wait_until("HTTP COMPLETED") { QueueAdapterSmoke.get_task(id).dig("status", "state") == "TASK_STATE_COMPLETED" }
  QueueAdapterSmoke.assert_state(id, "COMPLETED")
  completed = QueueAdapterSmoke.get_task(id)
  QueueAdapterSmoke.assert(completed.dig("artifacts", 0, "parts", 0, "text") == "adapter result", "HTTP Artifact missing")
  listing = QueueAdapterSmoke.result("ListTasks", { "contextId" => "http-async-context", "includeArtifacts" => true })
  QueueAdapterSmoke.assert(listing.fetch("tasks").find { |task| task.fetch("id") == id }.dig("artifacts", 0, "parts", 0, "text") == "adapter result", "ListTasks Artifact missing")

  running_cancel = QueueAdapterSmoke.send_task("hold")
  QueueAdapterSmoke.wait_until("running cancel Handler start") do
    QueueAdapterSmoke::Invocation.where(task_id: running_cancel).count == 1
  end
  QueueAdapterSmoke.result("CancelTask", { "id" => running_cancel })
  QueueAdapterSmoke.release(running_cancel)
  %w[fail reject].each do |text|
    outcome_id = QueueAdapterSmoke.send_task(text)
    expected = text == "fail" ? "TASK_STATE_FAILED" : "TASK_STATE_REJECTED"
    QueueAdapterSmoke.wait_until("HTTP #{expected}") { QueueAdapterSmoke.get_task(outcome_id).dig("status", "state") == expected }
  end
  QueueAdapterSmoke.wait_until("all queued HTTP work drained") { QueueAdapterSmoke.drained? }
  QueueAdapterSmoke.assert_state(running_cancel, "CANCELED")
  QueueAdapterSmoke.assert(!QueueAdapterSmoke.get_task(running_cancel).key?("artifacts"), "late Artifact survived cancellation")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: queued_cancel).count.zero?, "queued canceled Handler ran")

  QueueAdapterSmoke.stop_worker(worker)
  worker = nil
  restart_id = QueueAdapterSmoke.send_task("restart")
  QueueAdapterSmoke.assert_state(restart_id, "SUBMITTED")
  worker = QueueAdapterSmoke.start_worker(worker_log)
  QueueAdapterSmoke.wait_until("HTTP Task after worker restart") { QueueAdapterSmoke.get_task(restart_id).dig("status", "state") == "TASK_STATE_COMPLETED" }
  QueueAdapterSmoke.stop_worker(web)
  web = nil
  web = QueueAdapterSmoke.start_http(web_log)
  QueueAdapterSmoke.assert_state(id, "COMPLETED")
  QueueAdapterSmoke.assert(QueueAdapterSmoke.get_task(id).fetch("artifacts") == completed.fetch("artifacts"), "web restart lost Artifact")

  QueueAdapterSmoke::Invocation.all.each do |invocation|
    QueueAdapterSmoke.assert(invocation.principal_id == "adapter-owner" && invocation.idempotency_key == invocation.task_id,
      "HTTP principal/idempotency propagation failed")
    QueueAdapterSmoke.assert(QueueAdapterSmoke::Invocation.where(task_id: invocation.task_id).count == 1, "Handler ran twice")
  end
  QueueAdapterSmoke::RouteInvocation.group(:task_id).count.each_value do |count|
    QueueAdapterSmoke.assert(count == 1, "Router ran again in worker")
  end
  QueueAdapterSmoke.assert(QueueAdapterSmoke::RouteInvocation.count == 6, "not all HTTP Tasks routed once")
  puts "HTTP async #{ADAPTER}: PASS (SUBMITTED/WORKING/terminal, Get/List, owner, route once, cancel, web/worker restart)"
rescue StandardError
  [web_log, worker_log].each { |path| warn File.read(path) if File.exist?(path) }
  raise
ensure
  QueueAdapterSmoke.stop_worker(worker)
  QueueAdapterSmoke.stop_worker(web)
  FileUtils.remove_entry(SMOKE_ROOT) if File.directory?(SMOKE_ROOT)
end
