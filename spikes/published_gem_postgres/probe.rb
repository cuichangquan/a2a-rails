# frozen_string_literal: true

# Executed by bin/rails runner inside a generated, PostgreSQL-backed Rails
# application. The Gem itself MUST be loaded from installed RubyGems, never
# from this repository checkout. Every invocation is a fresh Rails process.
require "json"
require "securerandom"
require "rack/mock"
require "a2a-rails"

module PublishedGemPostgresProbe
  module_function

  STATE_FILE = ENV.fetch("A2A_SMOKE_STATE")
  OWNER_A = "tenant-A:client"
  OWNER_B = "tenant-B:client"

  def assert(condition, message)
    raise message unless condition
  end

  def assert_rpc(result, expected = nil)
    if expected
      assert(result.dig("error", "code") == expected, "expected RPC error #{expected}: #{result.inspect}")
    else
      assert(result.key?("result") && !result.key?("error"), "unexpected RPC failure: #{result.inspect}")
    end
    result
  end

  def rpc(token, method, params)
    request = Rack::MockRequest.new(Rails.application)
    response = request.post(
      "/a2a",
      "HTTP_HOST" => "localhost",
      "HTTPS" => "on",
      "rack.url_scheme" => "https",
      "HTTP_A2A_VERSION" => "1.0",
      "HTTP_AUTHORIZATION" => "Bearer #{token}",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(
        "jsonrpc" => "2.0", "id" => SecureRandom.uuid,
        "method" => method, "params" => params
      )
    )
    assert(response.status == 200, "#{method} HTTP #{response.status}: #{response.body}")
    JSON.parse(response.body)
  end

  def send_message(token, text)
    assert_rpc(rpc(token, "SendMessage", {
      "message" => {
        "messageId" => SecureRandom.uuid,
        "role" => "ROLE_USER",
        "contextId" => "shared-context",
        "parts" => [{ "text" => text }]
      }
    })).fetch("result").fetch("task")
  end

  def store
    A2A::Rails.configuration.resolve_task_store
  end

  def ids
    JSON.parse(File.read(STATE_FILE))
  end

  def record(id)
    A2A::Rails::Task::ActiveRecordStore::Record.find_by!(task_id: id)
  end

  def verify_installed_gem
    spec = Gem.loaded_specs.fetch("a2a-rails")
    assert(spec.version.to_s == "0.2.0.rc2", "not the expected released version")
    installed = File.realpath(spec.full_gem_path)
    source = File.realpath(ENV.fetch("A2A_RAILS_SOURCE_ROOT"))
    assert(!installed.start_with?(source + File::SEPARATOR), "loaded source tree instead of published Gem")
    assert(A2A::Rails.configuration.task_store == :active_record, "durable Store was not configured")
    assert(Rails.env.production?, "not running in production-shaped configuration")
    assert(ActiveRecord::Base.connection.adapter_name == "PostgreSQL", "not PostgreSQL")
    assert(ActiveRecord::Base.connection.select_value("SHOW server_version").start_with?("16."),
      "expected PostgreSQL 16 server")
    assert(ActiveRecord::Base.connection.data_source_exists?(:a2a_rails_tasks), "generated migration not applied")
    indexes = ActiveRecord::Base.connection.indexes(:a2a_rails_tasks)
    assert(indexes.any? { |index| index.unique && index.columns == ["task_id"] }, "missing Task unique index")
    assert(indexes.any? { |index| index.columns.first == "owner_id" }, "missing owner-scoped index")
    assert(store.is_a?(A2A::Rails::Task::ActiveRecordStore), "Runtime did not select ActiveRecordStore")
    puts "Installed Gem: #{installed} / Rails #{Rails.version} / PostgreSQL 16"
  end

  def phase_create
    card = Rack::MockRequest.new(Rails.application).get(
      "/.well-known/agent-card.json", "HTTP_HOST" => "localhost",
      "HTTPS" => "on", "rack.url_scheme" => "https"
    )
    assert(card.status == 200, "Agent Card HTTP #{card.status}: #{card.body}")
    json = JSON.parse(card.body)
    assert(json.dig("securitySchemes", "bearer", "httpAuthSecurityScheme", "scheme") == "Bearer",
      "Agent Card Bearer authentication mismatch")
    assert(json.fetch("supportedInterfaces").first.fetch("url") == "https://agents.example.test/a2a",
      "incorrect public Agent URL")

    alice1 = send_message("client-a", "alice-1")
    alice2 = send_message("client-a", "alice-2")
    bob = send_message("client-b", "bob-1")
    [alice1, alice2, bob].each do |task|
      assert(task.dig("status", "state") == "TASK_STATE_COMPLETED", "sync Task was not completed")
    end
    assert_rpc(rpc("client-b", "GetTask", "id" => alice1.fetch("id")), -32_001)
    assert_rpc(rpc("client-a", "GetTask", "id" => bob.fetch("id")), -32_001)
    alice_list = assert_rpc(rpc("client-a", "ListTasks",
      "contextId" => "shared-context", "pageSize" => 1)).fetch("result")
    assert(alice_list.fetch("totalSize") == 2, "cross-tenant count leakage")
    token = alice_list.fetch("nextPageToken")
    assert(!token.empty?, "missing pagination cursor")
    bob_list = assert_rpc(rpc("client-b", "ListTasks",
      "contextId" => "shared-context")).fetch("result")
    assert(bob_list.fetch("tasks").map { |task| task.fetch("id") } == [bob.fetch("id")],
      "Bob listed Alice's Task")
    assert_rpc(rpc("client-b", "ListTasks", {
      "contextId" => "shared-context", "pageSize" => 1, "pageToken" => token
    }), -32_602)
    assert(record(alice1.fetch("id")).expires_at > Time.now.utc + 3000, "terminal retention missing")

    lifecycle = A2A::Rails::Task::Lifecycle.new(store: store, principal_id: OWNER_A)
    pending = lifecycle.create(message: {
      message_id: SecureRandom.uuid, role: :user,
      parts: [{ text: "pending", media_type: "text/plain" }]
    }, context_id: "shared-context")
    racing = lifecycle.create(message: {
      message_id: SecureRandom.uuid, role: :user,
      parts: [{ text: "race", media_type: "text/plain" }]
    }, context_id: "shared-context")
    lifecycle.start(racing.fetch(:id))
    File.write(STATE_FILE, JSON.pretty_generate(
      "a1" => alice1.fetch("id"), "a2" => alice2.fetch("id"),
      "b1" => bob.fetch("id"), "pending" => pending.fetch(:id),
      "race" => racing.fetch(:id), "cursor" => token
    ))
    puts "Phase create: PASS"
  end

  def phase_restart
    state = ids
    assert(assert_rpc(rpc("client-a", "GetTask", "id" => state.fetch("a1")))
      .dig("result", "id") == state.fetch("a1"), "Task not persisted across Rails process restart")
    assert_rpc(rpc("client-b", "GetTask", "id" => state.fetch("a1")), -32_001)
    assert_rpc(rpc("client-b", "CancelTask", "id" => state.fetch("pending")), -32_001)
    result = assert_rpc(rpc("client-a", "CancelTask", "id" => state.fetch("pending")))
    assert(result.dig("result", "status", "state") == "TASK_STATE_CANCELED",
      "owner could not cancel persisted pending Task")
    second_page = assert_rpc(rpc("client-a", "ListTasks", {
      "contextId" => "shared-context", "pageSize" => 1,
      "pageToken" => state.fetch("cursor")
    })).fetch("result")
    assert(second_page.fetch("tasks").length == 1, "signed cursor failed after restart")
    assert_rpc(rpc("client-b", "ListTasks", {
      "contextId" => "shared-context", "pageSize" => 1,
      "pageToken" => state.fetch("cursor")
    }), -32_602)
    assert(record(state.fetch("pending")).state == "canceled", "cancellation not persisted")
    puts "Phase independent restart: PASS"
  end

  def phase_expire
    state = ids
    state.fetch_values("a1", "a2").each do |id|
      assert(record(id).state == "completed", "attempted to expire nonterminal Task")
      record(id).update!(expires_at: Time.now.utc - 120)
    end
    stats = store.maintenance_stats
    assert(stats.fetch(:expired) == 2, "expected exactly two artificially expired Tasks: #{stats}")
    assert(stats.fetch(:total) >= 5, "unexpected Task count")
    puts "Phase retention/expiry: PASS"
  end

  def phase_race
    target = ENV.fetch("A2A_RACE_TARGET")
    assert(%w[completed failed].include?(target), "unexpected race target")
    root = File.dirname(STATE_FILE)
    File.write(File.join(root, "ready-#{target}"), "ready")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 35
    until File.exist?(File.join(root, "race-go"))
      raise "race gate timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.02
    end
    state = store.transition(ids.fetch("race"), state: target.to_sym,
      timestamp: Time.now.utc, principal_id: OWNER_A).dig(:status, :state)
    File.write(File.join(root, "result-#{target}"), state.to_s)
    assert(%i[completed failed].include?(state), "nonterminal race outcome")
    puts "Phase concurrent #{target}: PASS"
  end

  def phase_final
    state = ids
    state.fetch_values("a1", "a2").each do |id|
      assert(!A2A::Rails::Task::ActiveRecordStore::Record.exists?(task_id: id),
        "expired Task not pruned: #{id}")
    end
    assert(assert_rpc(rpc("client-b", "GetTask", "id" => state.fetch("b1")))
      .dig("result", "id") == state.fetch("b1"), "prune removed non-expired Bob Task")
    assert(record(state.fetch("pending")).state == "canceled", "prune removed non-expired cancel")
    actual = record(state.fetch("race")).state
    results = %w[completed failed].map do |target|
      File.read(File.join(File.dirname(STATE_FILE), "result-#{target}")).strip
    end
    assert(%w[completed failed].include?(actual), "race Task not terminal")
    assert(results == [actual, actual], "concurrent terminal transitions disagreed: #{results.inspect}")
    assert(store.maintenance_stats.fetch(:expired) == 0, "expired backlog remained after prune")
    puts "Phase final PostgreSQL persistence/locking/prune: PASS"
  end

  def run
    verify_installed_gem
    case ENV.fetch("A2A_SMOKE_PHASE")
    when "create" then phase_create
    when "restart" then phase_restart
    when "expire" then phase_expire
    when "race" then phase_race
    when "final" then phase_final
    else raise "unknown smoke phase"
    end
  end
end

PublishedGemPostgresProbe.run
