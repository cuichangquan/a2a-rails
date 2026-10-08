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

message_id = SecureRandom.uuid
result = client.send_message(
  message: {
    message_id: message_id,
    role: "ROLE_USER",
    parts: [{ text: "Step 29-5c controlled public HTTPS echo smoke" }]
  }
)

case result.kind
when :message
  reply = result.message
  abort "Invalid direct Message" unless reply.is_a?(Hash) &&
    reply[:message_id].is_a?(String) && reply[:parts].is_a?(Array) && !reply[:parts].empty?
when :task
  task_id = result.task.fetch(:id)
  abort "Invalid Task ID" unless task_id.is_a?(String) && !task_id.empty?
  remote = client.get_task(id: task_id)
  abort "GetTask returned a different ID" unless remote.fetch(:id) == task_id
else
  abort "Unexpected SendMessage result kind"
end

puts "PASS: original Agent Card and expected JSON-RPC v1 HTTPS endpoint"
puts "PASS: ordinary Client constructor, default DNS, public CA and outbound message"
puts "PASS: #{result.kind == :task ? "GetTask" : "direct Message"} response"
puts "No custom resolver, trust root, proxy, auth callback or internal transport was used"
