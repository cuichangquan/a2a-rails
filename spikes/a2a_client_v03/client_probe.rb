# frozen_string_literal: true

# Step 29-1: standalone published SDK -> published a2a-rails 0.2.0 demo probe.
# The Rails server MUST be bound to loopback. This is NOT a production Client.
require "json"
require "net/http"
require "securerandom"
require "timeout"
require "uri"
require "a2a/client"

BASE = ENV.fetch("A2A_CLIENT_PROBE_BASE", "http://127.0.0.1:3000").sub(%r{/+\z}, "")
CARD_URL = "#{BASE}/.well-known/agent-card.json"

def check(condition, description)
  raise "FAIL: #{description}" unless condition
  puts "PASS: #{description}"
end

def message(text)
  {
    message_id: SecureRandom.uuid,
    role: "ROLE_USER",
    parts: [{ text: text }]
  }
end

def bounded(description)
  Timeout.timeout(15) { yield }
rescue Timeout::Error
  raise "Timed out: #{description}"
end

check(Gem.loaded_specs.fetch("agent2agent").version.to_s == "2.0.0", "SDK version is 2.0.0")
check(Gem.loaded_specs.fetch("a2a-rails").version.to_s == "0.2.0", "published a2a-rails Gem version is 0.2.0")
check(URI(BASE).host == "127.0.0.1", "probe only targets loopback")

raw_card = bounded("Agent Card download") do
  response = Net::HTTP.get_response(URI(CARD_URL))
  check(response.code == "200", "Agent Card HTTP 200")
  JSON.parse(response.body)
end

# Real SDK Agent Card fetch, which is relative to the client's base URL.
sdk_card = bounded("SDK Agent Card") { A2A::Client.new(BASE).agent_card }
check(sdk_card.to_h["name"] == "Echo Agent", "SDK Agent Card discovery")

interface = raw_card.fetch("supportedInterfaces").find do |candidate|
  candidate["protocolBinding"] == "JSONRPC" && candidate["protocolVersion"] == "1.0"
end
check(!interface.nil?, "Agent Card exposes JSONRPC protocolVersion 1.0")
endpoint = interface.fetch("url")
check(URI(endpoint).path == "/a2a", "use declared /a2a RPC path, not Card URL or /")
check(URI(endpoint).host == "127.0.0.1", "Agent Card declares loopback endpoint")

# SDK request methods POST to their configured connection URL, not necessarily
# the base URL used for Agent Card discovery.
client = A2A::Client.new(endpoint) do |connection|
  connection.headers["A2A-Version"] = "1.0"
  connection.options.open_timeout = 2
  connection.options.timeout = 8
end

result = bounded("SendMessage Task") { client.send_message(message: message("Hello")) }.to_h
task = result.fetch("task")
check(task.dig("status", "state") == "TASK_STATE_COMPLETED", "SendMessage returns completed Task")
check(task.dig("artifacts", 0, "parts", 0, "text") == "Echo: Hello", "Task includes Echo artifact")

task_id = task.fetch("id")
fetched = bounded("GetTask") { client.get_task(id: task_id) }.to_h
check(fetched["id"] == task_id && fetched.dig("status", "state") == "TASK_STATE_COMPLETED", "GetTask reads remote task")

listing = bounded("ListTasks") { client.list_tasks }.to_h
check(Array(listing["tasks"]).any? { |item| item["id"] == task_id }, "ListTasks includes submitted Task")

direct = bounded("SendMessage direct Message") { client.send_message(message: message("direct: hello")) }.to_h
check(direct.key?("message") && !direct.key?("task"), "SendMessage returns direct Message without Task")

begin
  bounded("CancelTask on terminal Task") { client.cancel_task(id: task_id) }
  raise "FAIL: terminal CancelTask unexpectedly succeeded"
rescue A2A::JsonRpcError => error
  puts "PASS: terminal CancelTask raises SDK JSON-RPC error (code=#{error.code})"
end

# Control case: show whether SDK config sends the version without explicit
# customization. Treat this as diagnostic; do not claim all remote agents reject.
begin
  bounded("default version behavior") { A2A::Client.new(endpoint).send_message(message: message("Version check")) }
  puts "OBSERVATION: SDK call without an explicit A2A-Version header succeeded"
rescue A2A::JsonRpcError => error
  puts "OBSERVATION: SDK call without A2A-Version header rejected (code=#{error.code})"
end

# Faraday test adapter: verify host config can inject authorization and limits.
# Uses a fake token, NEVER production credentials. No additional server needed.
seen = nil
mock_client = A2A::Client.new(endpoint) do |connection|
  connection.headers["A2A-Version"] = "1.0"
  connection.headers["Authorization"] = "Bearer fake-spike-token"
  connection.options.timeout = 4
  connection.options.open_timeout = 2
  connection.adapter :test do |stub|
    stub.post("/a2a") do |env|
      seen = env
      [200, { "content-type" => "application/json" }, JSON.generate({
        jsonrpc: "2.0", id: 1,
        result: {
          task: { id: "mock-task", contextId: "mock-context",
                  status: { state: "TASK_STATE_SUBMITTED" } }
        }
      })]
    end
  end
end

mock = bounded("Faraday configuration") { mock_client.send_message(message: message("fixture only")) }.to_h
check(mock.dig("task", "id") == "mock-task", "custom Faraday adapter response")
check(seen && seen.request_headers["Authorization"] == "Bearer fake-spike-token",
  "host can inject outbound Authorization header")
check(seen.request_headers["A2A-Version"] == "1.0", "host can inject A2A v1 header")
check(seen.request.timeout == 4 && seen.request.open_timeout == 2,
  "host can configure Faraday request timeouts")

puts "STEP 29-1 SDK CLIENT PROBE PASS (loopback-only integration, not production-safe)"
