# frozen_string_literal: true

# Step 29-5b: actual public Rails Client operations against official Python
# and Go SDK A2A Servers, each running native HTTPS with unmodified Agent Card.
# Loopback pinning/CA is a TEST-ONLY internal override. The normal Client
# constructor continues to refuse local/private targets.
require "a2a-rails"
require "securerandom"

if ENV["A2A_RAILS_USE_INSTALLED_GEM"] == "1"
  expected = ENV.fetch("A2A_RAILS_EXPECTED_VERSION")
  source_root = ENV.fetch("A2A_RAILS_SOURCE_ROOT")
  spec = Gem.loaded_specs.fetch("a2a-rails")
  verify_path = File.realpath(spec.full_gem_path)
  raise "unexpected installed candidate version" unless A2A::Rails::VERSION == expected
  raise "source checkout used instead of installed Gem" if
    verify_path.start_with?(File.realpath(source_root) + File::SEPARATOR)
  puts "Verified installed Client Gem: #{verify_path} (#{A2A::Rails::VERSION})"
end

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
# Keep Card discovery public. Only the RPC's exact approved HTTPS origin
# receives a test-only bearer token. The normal Client constructor's DNS
# rejection above remains unchanged; injected resolver is test-only.
def client_with_test_rpc_token(policy:, transport:, token:)
  options = {
    agent_card_url: "#{BASE}/.well-known/agent-card.json",
    allowed_origins: [BASE], open_timeout: 2, read_timeout: 5, total_timeout: 8
  }
  credentials = token.nil? ? {} : {
    authorization: -> { token }, credential_origin: BASE
  }
  instance = A2A::Rails::Client.new(**options, **credentials)
  resolver = A2A::Rails::Client::AgentCardResolver.new(
    agent_card_url: options.fetch(:agent_card_url),
    policy: policy, transport: transport, **credentials
  )
  instance.instance_variable_set(:@resolver, resolver)
  instance
end

primary_go_token = AGENT == "go" ? "Bearer go-test-tenant-a-token" : nil
client = client_with_test_rpc_token(
  policy: policy, transport: transport, token: primary_go_token
)

card = client.agent_card
verify!(card[:name] == "Official #{AGENT.capitalize} SDK Echo", "official #{AGENT} SDK Card used")
chosen = card.fetch(:supported_interfaces).find do |entry|
  entry[:protocol_binding] == "JSONRPC" && entry[:protocol_version] == "1.0"
end
verify!(chosen && chosen[:url] == "#{BASE}#{RPC_PATH}",
        "unmodified Agent Card declares exact native HTTPS JSONRPC 1.0 URL")

if AGENT == "go"
  bearer = card.dig(:security_schemes, "interopBearer")
  verify!(bearer.is_a?(Hash), "official Go Card advertises test-only bearer scheme")
  verify!(!card.fetch(:security_requirements).empty?,
          "official Go Card declares RPC credential requirement")
end

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

# Step 29-5n: exercise rich Part representations created by the *official*
# Python/Go SDKs, NOT a Rails-generated fixture or a synthetic wire response.
rich = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "rich: return native official SDK text/data/raw/url" }]
})
verify!(rich.kind == :message, "#{AGENT} official SDK returned rich direct Message")
parts = rich.message.fetch(:parts)
verify!(parts.length == 4, "#{AGENT} direct Message contains four native Part variants")
verify!(parts[0][:text].include?("#{AGENT.capitalize}: rich"), "rich text Part preserved")
verify!(parts[1].dig(:data, "businessId") == "#{AGENT}-123",
        "native #{AGENT} Data Part preserves businessId")
verify!(parts[1].dig(:data, "nested", "keepCamelCase").is_a?(Array),
        "native Data Part preserves opaque nested camelCase keys and arrays")
verify!(parts[2][:raw] == ["#{AGENT}-bytes"].pack("m0"),
        "native #{AGENT} raw bytes remain base64 encoded")
verify!(parts[3][:url] == "https://files.example/#{AGENT}.pdf",
        "native URL Part preserved as an unfetched string")
verify!(rich.message.frozen? && parts[1][:data].frozen?,
        "rich protocol output is deeply immutable")

def send_test_task(client, marker)
  result = client.send_message(message: {
    message_id: SecureRandom.uuid,
    role: "ROLE_USER",
    parts: [{ text: marker }]
  })
  verify!(result.kind == :task, "official SDK returns Task for #{marker}")
  result.task
end

rich_task = send_test_task(client, "rich-task: native SDK Artifact with File/Data")
verify!(rich_task.dig(:status, :state) == "TASK_STATE_COMPLETED",
        "#{AGENT} rich Task reaches completed state")
native_parts = rich_task.dig(:artifacts, 0, :parts)
verify!(native_parts.is_a?(Array) && native_parts.size >= 3,
        "#{AGENT} Task contains native SDK artifact text/data/raw")
verify!(native_parts.any? { |part| part[:data].is_a?(Hash) &&
  part[:data]["businessId"] == "#{AGENT}-task-123" },
        "#{AGENT} Task Artifact preserves native nested Data")
verify!(native_parts.any? { |part| part[:raw].is_a?(String) && !part[:raw].empty? },
        "#{AGENT} Task Artifact preserves file/raw bytes in base64")
stored = client.get_task(id: rich_task.fetch(:id), history_length: 1)
verify!(stored.fetch(:id) == rich_task.fetch(:id),
        "#{AGENT} GetTask loads persistent task from SDK Task Store")
verify!(stored.dig(:artifacts, 0, :parts).is_a?(Array),
        "#{AGENT} GetTask roundtrips native Artifact Parts")
verify!(stored.fetch(:status).fetch(:state) == "TASK_STATE_COMPLETED",
        "#{AGENT} GetTask preserves terminal state")

waiting = send_test_task(client, "input-required: pause and await human")
verify!(waiting.dig(:status, :state) == "TASK_STATE_INPUT_REQUIRED",
        "#{AGENT} SDK retains nonterminal INPUT_REQUIRED state")
waiting_stored = client.get_task(id: waiting.fetch(:id))
verify!(waiting_stored.dig(:status, :state) == "TASK_STATE_INPUT_REQUIRED",
        "#{AGENT} GetTask preserves parked state")

# A rejected SDK operation is a capability *verification gap*, not PASS.
# -31401/-31403 are auth failures (not evidence of unsupported ListTasks).
# Other SDK codes remain explicitly unverified; no unexpected Rails
# exception or malformed response is swallowed.
def remote_capability_gap(error)
  case error.code
  when -31401 then "AUTH_REQUIRED(code=-31401)"
  when -31403 then "FORBIDDEN(code=-31403)"
  when -32601, -32004 then "UNSUPPORTED(code=#{error.code})"
  else "REMOTE_ERROR_UNVERIFIED(code=#{error.code})"
  end
end

capabilities = {}
begin
  canceled = client.cancel_task(id: waiting.fetch(:id))
  verify!(canceled.dig(:status, :state) == "TASK_STATE_CANCELED",
          "#{AGENT} CancelTask transitions parked Task to CANCELED")
  verify!(client.get_task(id: waiting.fetch(:id)).dig(:status, :state) ==
          "TASK_STATE_CANCELED", "#{AGENT} GetTask observes canceled state")
  capabilities[:cancel_task] = "PASS"
rescue A2A::Rails::Client::RemoteError => error
  capabilities[:cancel_task] = remote_capability_gap(error)
  puts "CAPABILITY-GAP: #{AGENT} SDK CancelTask #{capabilities.fetch(:cancel_task)}"
end

begin
  first_page = client.list_tasks(page_size: 1, include_artifacts: false)
  verify!(first_page.tasks.size == 1, "#{AGENT} SDK ListTasks honors page_size=1")
  verify!(first_page.next_page_token.is_a?(String),
          "#{AGENT} ListTasks cursor has a valid string type")
  if first_page.next_page_token.empty?
    # We have already created two Tasks above; a single-task first page with
    # no cursor is not a valid demonstration of pagination.
    raise "FAIL: #{AGENT} ListTasks no cursor despite multiple SDK tasks"
  end
  second_page = client.list_tasks(page_size: 1, page_token: first_page.next_page_token)
  verify!(second_page.tasks.size >= 1 &&
          first_page.tasks.first.fetch(:id) != second_page.tasks.first.fetch(:id),
          "#{AGENT} ListTasks returns a distinct cursor page")
  capabilities[:list_tasks] = "PASS"
rescue A2A::Rails::Client::RemoteError => error
  capabilities[:list_tasks] = remote_capability_gap(error)
  puts "CAPABILITY-GAP: #{AGENT} SDK ListTasks #{capabilities.fetch(:list_tasks)}"
end

# Step 29-5q Go SDK: authenticate using the *official* a2asrv interceptor
# and default owner-scoped Task Store. Negative calls are real SDK JSON-RPC,
# never simulated error envelopes or a mocked Task Store.
if AGENT == "go"
  anonymous = client_with_test_rpc_token(policy: policy, transport: transport, token: nil)
  invalid = client_with_test_rpc_token(
    policy: policy, transport: transport, token: "Bearer invalid-go-test-token"
  )
  [anonymous, invalid].each do |no_access|
    begin
      no_access.list_tasks(page_size: 1)
      raise "FAIL: Go SDK exposed ListTasks without valid bearer identity"
    rescue A2A::Rails::Client::RemoteError => error
      verify!(error.code == -31401 && error.cause.nil?,
              "Go SDK denies missing/invalid ListTasks identity with -31401")
    end
  end

  other = client_with_test_rpc_token(
    policy: policy, transport: transport, token: "Bearer go-test-tenant-b-token"
  )
  other_task = send_test_task(other, "rich-task: tenant B separate owner")
  verify!(other_task.dig(:status, :state) == "TASK_STATE_COMPLETED",
          "authenticated Go tenant B can create own Task")

  # The Go SDK's default Task Store applies *its own* owner scoping.
  # Do not replace it with a permissive test store or fixed identity.
  tenant_a_tasks = [rich_task.fetch(:id), waiting.fetch(:id)]
  a_page = client.list_tasks(page_size: 1)
  a_next = client.list_tasks(page_size: 1, page_token: a_page.next_page_token)
  verify!(a_page.tasks.size == 1 && a_next.tasks.size == 1 &&
          a_page.tasks.first.fetch(:id) != a_next.tasks.first.fetch(:id) &&
          (a_page.tasks + a_next.tasks).all? { |t| tenant_a_tasks.include?(t.fetch(:id)) },
          "Go tenant A authenticated cursor paging returns own Tasks only")

  b_page = other.list_tasks(page_size: 1)
  verify!(b_page.tasks.size == 1 &&
          b_page.tasks.first.fetch(:id) == other_task.fetch(:id) &&
          b_page.next_page_token.empty?,
          "Go tenant B lists only its own Task, no A Task or cursor")

  [[client, other_task.fetch(:id)], [other, rich_task.fetch(:id)]].each do |caller, foreign_id|
    begin
      caller.get_task(id: foreign_id)
      raise "FAIL: Go SDK let another tenant read a foreign Task"
    rescue A2A::Rails::Client::RemoteError => error
      verify!(error.code == -32001 && error.cause.nil?,
              "Go SDK masks cross-owner GetTask as sanitized -32001 not-found")
    end
  end

  puts "STEP 29-5q GO SDK AUTHENTICATED LISTTASKS: PASS (two pages, cross-owner denial)"
end

begin
  client.get_task(id: "not-found-native-#{SecureRandom.uuid}")
  raise "FAIL: #{AGENT} SDK returned Task for nonexistent ID"
rescue A2A::Rails::Client::RemoteError => error
  verify!(error.code.is_a?(Integer) && error.cause.nil?,
          "#{AGENT} SDK remote missing-task error is typed and sanitized")
  capabilities[:get_missing_task] = "PASS"
end
puts "STEP 29-5n SDK CAPABILITIES #{AGENT.upcase}: #{capabilities.inspect}"

verify!(policy.resolved_urls.include?("#{BASE}/.well-known/agent-card.json"),
        "Client fetched official Agent Card from pinned local HTTPS socket")
verify!(policy.resolved_urls.include?("#{BASE}#{RPC_PATH}"),
        "Client used exactly declared independent SDK RPC path")
verify!(policy.resolved_urls.all? { |u| u.start_with?("#{BASE}/") },
        "all attempted requests are in exact approved HTTPS origin")

puts "STEP 29-5b OFFICIAL #{AGENT.upcase} SERVER HTTPS OUTBOUND: PASS"
