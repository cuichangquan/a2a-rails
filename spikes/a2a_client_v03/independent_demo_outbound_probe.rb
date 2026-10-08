# frozen_string_literal: true

# Step 29-5a: the MAIN-SOURCE outbound Client calls the independent Demo
# running the PUBLISHED a2a-rails 0.2.0 Gem. HTTPS is terminated by a
# loopback-only test bridge because the Demo itself advertises an HTTP URL.
# Do not install the loopback policy in an application or weaken production
# OutboundPolicy to support this test.
require "a2a-rails"
require "json"
require "securerandom"

EXPECTED_GEM_PATH = File.expand_path("../../lib", __dir__)
unless $LOADED_FEATURES.any? { |path| path.start_with?(EXPECTED_GEM_PATH) && path.end_with?("/a2a-rails.rb") }
  abort("FAIL: outbound Client must be loaded from the main checkout")
end

BASE = ENV.fetch("STEP29_5_DEMO_TLS_BASE", "https://echo-agent.test:3443")
CA_FILE = ENV.fetch("STEP29_5_DEMO_TLS_CA")

def verify!(condition, label)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

class TestOnlyPinnedLoopbackPolicy < A2A::Rails::Client::OutboundPolicy
  attr_reader :checked_paths, :checked_origins

  def initialize(allowed_origins:)
    super
    @checked_paths = []
    @checked_origins = []
  end

  def resolve!(url)
    # Enforce EXACT configured HTTPS origin and path syntax, but supply the
    # local one-off test socket instead of resolving real DNS. Production
    # implementation still rejects loopback and cannot opt into this policy
    # through the public constructor.
    uri = validate_url!(url)
    @checked_paths << uri.path
    @checked_origins << "#{uri.scheme}://#{uri.host}:#{uri.port}"
    A2A::Rails::Client::OutboundPolicy::Target.new(
      url: uri.to_s.freeze,
      origin: "#{uri.scheme}://#{uri.host}:#{uri.port}".freeze,
      host: uri.host.freeze,
      port: uri.port,
      addresses: ["127.0.0.1"].freeze
    ).freeze
  end
end

verify!(BASE == "https://echo-agent.test:3443", "isolated TLS test origin is fixed")
verify!(File.file?(CA_FILE), "test CA certificate is available")

strict = A2A::Rails::Client.new(
  agent_card_url: "#{BASE}/.well-known/agent-card.json",
  allowed_origins: [BASE],
  open_timeout: 2,
  read_timeout: 5,
  total_timeout: 8
)
verify!(strict.is_a?(A2A::Rails::Client), "public Client constructed")
begin
  strict.agent_card
  raise "FAIL: production SSRF policy unexpectedly contacted loopback"
rescue A2A::Rails::Client::TransportError => error
  verify!(%i[dns_failure blocked_ip].include?(error.reason),
    "production Client refuses special test-only loopback endpoint")
end

policy = TestOnlyPinnedLoopbackPolicy.new(allowed_origins: [BASE])
transport = A2A::Rails::Client::PinnedHttpsTransport.new(
  policy: policy, ca_file: CA_FILE, open_timeout: 2,
  read_timeout: 5, total_timeout: 8
)
resolver = A2A::Rails::Client::AgentCardResolver.new(
  agent_card_url: "#{BASE}/.well-known/agent-card.json",
  policy: policy, transport: transport
)

# Explicit, contained white-box test seam. There is no public option to
# replace the production policy, transport, TLS CA or DNS checker.
strict.instance_variable_set(:@resolver, resolver)
client = strict

card = client.agent_card
verify!(card[:name] == "Echo Agent", "published Demo Agent Card discovered via TLS")
interface = card[:supported_interfaces].find do |entry|
  entry[:protocol_binding] == "JSONRPC" && entry[:protocol_version] == "1.0"
end
verify!(interface && interface[:url] == "#{BASE}/a2a",
  "Client selects declared JSONRPC 1.0 HTTPS endpoint")

result = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "Hello from outgoing Client" }]
})
verify!(result.kind == :task, "real independent Demo SendMessage returns Task")
task = result.task
verify!(task.dig(:status, :state) == "TASK_STATE_COMPLETED",
  "remote Task has completed")
verify!(task.dig(:artifacts, 0, :parts, 0, :text) == "Echo: Hello from outgoing Client",
  "remote Echo Handler result was decoded into an Artifact")
verify!(task.frozen?, "public Task DTO is immutable")

remote_id = task.fetch(:id)
fetched = client.get_task(id: remote_id, history_length: 0)
verify!(fetched.fetch(:id) == remote_id &&
  fetched.dig(:status, :state) == "TASK_STATE_COMPLETED",
  "GetTask fetches Task from remote Gem 0.2.0")
verify!(fetched.frozen?, "fetched Task is immutable")

page = client.list_tasks(page_size: 10, include_artifacts: false, history_length: 0)
verify!(page.tasks.any? { |row| row.fetch(:id) == remote_id },
  "ListTasks includes Task created by outbound Client")
verify!(page.next_page_token.is_a?(String) && page.page_size.is_a?(Integer),
  "ListTasks cursor and page count use Ruby DTO")

direct = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "direct: hello" }]
})
verify!(direct.kind == :message && direct.task.nil?,
  "SendMessage returns direct Message without Task")
verify!(direct.message.fetch(:role) == "ROLE_AGENT" &&
  direct.message.dig(:parts, 0, :text) == "Echo: direct: hello",
  "direct Message content matches independent Demo response")

begin
  client.cancel_task(id: remote_id)
  raise "FAIL: terminal CancelTask should raise A2A error"
rescue A2A::Rails::Client::RemoteError => error
  verify!(error.code == -32_002, "terminal CancelTask retains protocol error code -32002")
end

verify!(policy.checked_paths.include?("/.well-known/agent-card.json") &&
  policy.checked_paths.include?("/a2a"),
  "actual TLS requests use separately validated Card and RPC paths")
verify!(policy.checked_origins.uniq == [BASE],
  "all requests remain on exact approved HTTPS origin")
puts "STEP 29-5a INDEPENDENT DEMO OUTBOUND CLIENT HTTPS: PASS"
