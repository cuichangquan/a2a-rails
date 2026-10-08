# frozen_string_literal: true

# Manually gated Step 29-5c public egress probe. Unlike prior loopback tests,
# this uses only the normal Client constructor, default DNS and public CA trust.
# Never use an unapproved third-party Agent or pass credentials to this probe.
require "a2a-rails"
require "securerandom"
require "uri"

def required_environment(name)
  value = ENV.fetch(name) { abort "Missing controlled egress configuration: #{name}" }
  abort "Missing controlled egress configuration: #{name}" if value.empty?
  value
end

abort "Controlled endpoint approval is required" unless
  ENV["A2A_PUBLIC_EGRESS_APPROVED"] == "controlled-endpoint-no-auth"

card_url = required_environment("A2A_PUBLIC_CARD_URL")
rpc_url = required_environment("A2A_PUBLIC_EXPECTED_RPC_URL")
allowed_origins = required_environment("A2A_PUBLIC_ALLOWED_ORIGINS").split(",").map(&:strip)
abort "Invalid origin allowlist" if allowed_origins.empty? || allowed_origins.any?(&:empty?)

[card_url, rpc_url].each do |url|
  uri = URI.parse(url)
  abort "Endpoint must be HTTPS with a public hostname" unless uri.is_a?(URI::HTTPS) && uri.host
  origin = uri.port == 443 ? "https://#{uri.host}" : "https://#{uri.host}:#{uri.port}"
  abort "Unapproved endpoint origin" unless allowed_origins.include?(origin)
end

client = A2A::Rails::Client.new(
  agent_card_url: card_url,
  allowed_origins: allowed_origins,
  open_timeout: 3,
  read_timeout: 10,
  total_timeout: 15
)

card = client.agent_card
interface = card.fetch(:supported_interfaces).find do |entry|
  entry[:protocol_binding] == "JSONRPC" && entry[:protocol_version] == "1.0"
end
abort "Unexpected or missing JSON-RPC v1 interface" unless interface &&
  interface.fetch(:url) == rpc_url

# The controlled Agent must support BOTH an immediate reply to "direct:"
# and a completed Task + text Artifact to "task:". A one-sided smoke is
# insufficient for the Step 29-5c positive acceptance criteria.
def has_echo?(parts, marker)
  parts.is_a?(Array) && parts.any? do |part|
    part.is_a?(Hash) && part[:text].is_a?(String) && part[:text].include?(marker)
  end
end

nonce = SecureRandom.hex(12)
direct = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "direct: public-egress-#{nonce}" }]
})
abort "FAIL: expected immediate direct Message" unless direct.kind == :message &&
  direct.task.nil? && direct.message.is_a?(Hash) &&
  direct.message[:role] == "ROLE_AGENT" &&
  has_echo?(direct.message[:parts], nonce)

task_result = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "task: public-egress-#{nonce}" }]
})
abort "FAIL: expected remote Task" unless task_result.kind == :task &&
  task_result.message.nil? && task_result.task.is_a?(Hash)

id = task_result.task.fetch(:id)
abort "FAIL: invalid remote Task ID" unless id.is_a?(String) && !id.empty?

# The Client does not implicitly retry or poll. This bounded explicit polling
# verifies GetTask while allowing asynchronous official SDK execution.
task = nil
6.times do
  task = client.get_task(id: id)
  break if task.dig(:status, :state) == "TASK_STATE_COMPLETED"
  sleep 0.25
end

artifacts = task[:artifacts]
abort "FAIL: missing completed Task or echo Artifact" unless
  task.fetch(:id) == id &&
  task.dig(:status, :state) == "TASK_STATE_COMPLETED" &&
  artifacts.is_a?(Array) &&
  artifacts.any? { |artifact| artifact.is_a?(Hash) && has_echo?(artifact[:parts], nonce) }

puts "PASS: original Agent Card advertises expected JSON-RPC v1 HTTPS endpoint"
puts "PASS: ordinary Client constructor, default DNS and public CA TLS"
puts "PASS: direct Message echoed a unique request nonce"
puts "PASS: Task, GetTask and Artifact echoed a unique request nonce"
puts "NOTE: actual Rails Client socket IP still requires independent runner/network evidence"
