# frozen_string_literal: true

# Step 29-5b: actual public Rails Client operations against official Python
# and Go SDK A2A Servers, each running native HTTPS with unmodified Agent Card.
# Loopback pinning/CA is a TEST-ONLY internal override. The normal Client
# constructor continues to refuse local/private targets.
require "a2a-rails"
require "securerandom"

AGENT = ENV.fetch("STEP29_5B_AGENT")
raise "unsupported official agent test" unless %w[python go].include?(AGENT)

PORT = AGENT == "python" ? 3444 : 3445
HOST = "#{AGENT}-agent.test"
BASE = "https://#{HOST}:#{PORT}"
RPC_PATH = AGENT == "python" ? "/python/a2a/jsonrpc" : "/go/agent/jsonrpc"
CA_FILE = ENV.fetch("STEP29_5B_CA")
raise "test CA certificate missing" unless File.file?(CA_FILE)

def verify!(condition, message)
  raise "FAIL: #{message}" unless condition
  puts "PASS: #{message}"
end

class OfficialSDKTestOnlyLoopbackPolicy < A2A::Rails::Client::OutboundPolicy
  attr_reader :resolved_urls

  def initialize(allowed_origins:)
    super
    @resolved_urls = []
  end

  def resolve!(url)
    uri = validate_url!(url)
    @resolved_urls << uri.to_s
    A2A::Rails::Client::OutboundPolicy::Target.new(
      url: uri.to_s.freeze,
      origin: "https://#{uri.host}:#{uri.port}".freeze,
      host: uri.host.freeze,
      port: uri.port,
      addresses: ["127.0.0.1"].freeze
    ).freeze
  end
end

client = A2A::Rails::Client.new(
  agent_card_url: "#{BASE}/.well-known/agent-card.json",
  allowed_origins: [BASE],
  open_timeout: 2, read_timeout: 5, total_timeout: 8
)
verify!(client.is_a?(A2A::Rails::Client), "public Rails Client initialized")

# A normal production Client must NEVER connect to this fake DNS/loopback
# test host. It fails closed at policy DNS stage before network connection.
begin
  client.agent_card
  raise "FAIL: production Client bypassed loopback/DNS target validation"
rescue A2A::Rails::Client::TransportError => error
  verify!(%i[dns_failure blocked_ip].include?(error.reason),
          "production Client cannot connect to synthetic loopback-only test host")
end

# The only test seam is inaccessible to normal public Client constructors.
policy = OfficialSDKTestOnlyLoopbackPolicy.new(allowed_origins: [BASE])
transport = A2A::Rails::Client::PinnedHttpsTransport.new(
  policy: policy, ca_file: CA_FILE,
  open_timeout: 2, read_timeout: 5, total_timeout: 8
)
resolver = A2A::Rails::Client::AgentCardResolver.new(
  agent_card_url: "#{BASE}/.well-known/agent-card.json",
  policy: policy, transport: transport
)
client.instance_variable_set(:@resolver, resolver)

card = client.agent_card
verify!(card[:name] == "Official #{AGENT.capitalize} SDK Echo", "official #{AGENT} SDK Card used")
chosen = card.fetch(:supported_interfaces).find do |entry|
  entry[:protocol_binding] == "JSONRPC" && entry[:protocol_version] == "1.0"
end
verify!(chosen && chosen[:url] == "#{BASE}#{RPC_PATH}",
        "unmodified Agent Card declares exact native HTTPS JSONRPC 1.0 URL")

message_text = AGENT == "python" ? "direct: hello from Rails" : "Hello from Rails"
direct = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: message_text }]
})
verify!(direct.kind == :message && direct.task.nil?, "real SDK SendMessage returns direct Message")
verify!(direct.message[:role] == "ROLE_AGENT", "direct Message has Agent role")
expected = AGENT == "python" ? "Python: #{message_text}" : "Go: hello from official SDK"
verify!(direct.message.dig(:parts, 0, :text) == expected,
        "direct Message content comes from official #{AGENT} server")
verify!(direct.message.frozen?, "direct Message is deeply immutable")

if AGENT == "python"
  result = client.send_message(message: {
    message_id: SecureRandom.uuid,
    role: "ROLE_USER",
    parts: [{ text: "task: hello" }]
  })
  verify!(result.kind == :task && result.message.nil?, "official Python SDK returns a Task")
  task = result.task
  verify!(task.dig(:status, :state) == "TASK_STATE_COMPLETED", "Python Task completed")
  verify!(task.dig(:artifacts, 0, :parts, 0, :text) == "Python: task: hello",
          "Python SDK Artifact round trips through Rails Client")
  verify!(client.get_task(id: task.fetch(:id)).fetch(:id) == task[:id],
          "GetTask retrieves official Python server Task")
end

verify!(policy.resolved_urls.include?("#{BASE}/.well-known/agent-card.json"),
        "Client fetched official Agent Card from pinned local HTTPS socket")
verify!(policy.resolved_urls.include?("#{BASE}#{RPC_PATH}"),
        "Client used exactly declared independent SDK RPC path")
verify!(policy.resolved_urls.all? { |u| u.start_with?("#{BASE}/") },
        "all attempted requests are in exact approved HTTPS origin")

puts "STEP 29-5b OFFICIAL #{AGENT.upcase} SERVER HTTPS OUTBOUND: PASS"
