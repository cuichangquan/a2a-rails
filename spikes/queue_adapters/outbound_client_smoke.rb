# frozen_string_literal: true

# Step 29-5o: REAL separately running Solid Queue / Sidekiq worker calls the
# unreleased outbound Client against test-only pinned native TLS servers.
# No inline adapter, in-process perform_now, production credentials or GCP.
ENV["OUTBOUND_CLIENT_SMOKE"] = "1"
require_relative "support"
require "openssl"
require "socket"
require "securerandom"

class QueuedOutboundHttpsAgent
  attr_reader :port, :requests

  def initialize(certificate:, key:, reference_id:, expected_token:, mode:)
    @reference_id = reference_id
    @expected_token = "Bearer #{expected_token}"
    @mode = mode
    @socket = TCPServer.new("127.0.0.1", 0)
    @port = @socket.addr[1]
    @requests = Queue.new
    context = OpenSSL::SSL::SSLContext.new
    context.cert = certificate
    context.key = key
    ssl_server = OpenSSL::SSL::SSLServer.new(@socket, context)
    @thread = Thread.new do
      loop do
        peer = nil
        begin
          peer = ssl_server.accept
          handle_request(peer)
        rescue OpenSSL::SSL::SSLError, IOError, SystemCallError, EOFError
          break if @socket.closed?
        ensure
          peer&.close rescue nil
        end
      end
    end
  end

  def origin
    "https://queued-agent.test:#{port}"
  end

  def close
    @socket.close rescue nil
    @thread.join(1)
    @thread.kill if @thread.alive?
    @thread.join
  end

  private

  def handle_request(peer)
    first = peer.gets
    return if first.nil?

    verb, path, = first.strip.split(" ", 3)
    headers = {}
    while (line = peer.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.downcase] = value.to_s.strip
    end
    body = peer.read(headers.fetch("content-length", "0").to_i)
    @requests << { method: verb, path: path, headers: headers, body: body }

    if verb == "GET" && path == "/.well-known/agent-card.json"
      response = {
        name: "Queue Worker Agent", description: "Test-only HTTPS",
        version: "1.0", capabilities: { streaming: false },
        defaultInputModes: ["text/plain"], defaultOutputModes: ["text/plain"],
        skills: [{ id: "echo", name: "Echo", description: "Echo", tags: ["test"] }],
        supportedInterfaces: [{
          protocolBinding: "JSONRPC", protocolVersion: "1.0",
          url: "#{origin}/rpc"
        }]
      }
      respond(peer, "200 OK", JSON.generate(response))
      return
    end

    unless verb == "POST" && path == "/rpc" && headers["authorization"] == @expected_token
      respond(peer, "401 Unauthorized", "{}")
      return
    end

    # The network has already received the full SendMessage and could have
    # executed it. Withhold the reply: timeout MUST NOT cause an automatic
    # duplicate SendMessage or an "executed=false" outcome.
    if @mode == "timeout"
      sleep 0.8
      return
    end

    request = JSON.parse(body)
    response = {
      jsonrpc: "2.0", id: request.fetch("id"),
      result: { message: {
        messageId: "server-message-#{@reference_id}",
        role: "ROLE_AGENT", parts: [{ text: "safe-reply" }]
      } }
    }
    respond(peer, "200 OK", JSON.generate(response))
  end

  def respond(peer, status, body)
    peer.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n" \
      "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  end
end

def create_test_ca!(root)
  key = OpenSSL::PKey::RSA.new(2048)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = 1
  name = OpenSSL::X509::Name.parse("/CN=queued-agent.test")
  cert.subject = name
  cert.issuer = name
  cert.public_key = key.public_key
  cert.not_before = Time.now - 60
  cert.not_after = Time.now + 3600
  ext = OpenSSL::X509::ExtensionFactory.new
  ext.subject_certificate = cert
  ext.issuer_certificate = cert
  cert.add_extension(ext.create_extension("basicConstraints", "CA:TRUE", true))
  cert.add_extension(ext.create_extension("keyUsage", "digitalSignature,keyEncipherment,keyCertSign", true))
  cert.add_extension(ext.create_extension("subjectAltName", "DNS:queued-agent.test"))
  cert.sign(key, OpenSSL::Digest::SHA256.new)
  File.write(File.join(root, "outbound-test-ca.pem"), cert.to_pem, mode: "w", perm: 0o600)
  [cert, key]
end

module QueueAdapterSmoke
  module_function

  def queue_payloads
    if ADAPTER == "solid_queue"
      SolidQueue::Job.all.map(&:arguments)
    else
      require "sidekiq/api"
      Sidekiq::Queue.new("default").map { |j| j.args.first }
    end
  end

  def outbound_queue_drained?
    if ADAPTER == "solid_queue"
      SolidQueue::Job.where(finished_at: nil).count.zero?
    else
      require "sidekiq/api"
      Sidekiq::Queue.new("default").size.zero? && Sidekiq::Workers.new.size.zero?
    end
  end
end

worker = nil
servers = []
root = SMOKE_ROOT
log = File.join(root, "outbound-worker.log")

begin
  initialize_smoke_schema!
  ActiveRecord::Schema.define do
    create_table(:smoke_outbound_calls) do |table|
      table.string :reference_id, null: false
      table.integer :worker_pid, null: false
      table.string :outcome, null: false
      table.string :reason
      table.string :remote_message_id
    end
    add_index :smoke_outbound_calls, :reference_id, unique: true
  end

  cert, private_key = create_test_ca!(root)
  modes = {
    "tenant_a" => "success",
    "tenant_b" => "success",
    "timeout" => "timeout",
    "denied" => "wrong_origin"
  }
  manifest = modes.to_h do |reference_id, mode|
    token = "worker-fake-token-#{reference_id}"
    server = QueuedOutboundHttpsAgent.new(
      certificate: cert, key: private_key,
      reference_id: reference_id, expected_token: token, mode: mode
    )
    servers << server
    [reference_id, { origin: server.origin, mode: mode, token: token }]
  end
  File.write(File.join(root, "outbound-manifest.json"),
    JSON.generate(manifest), mode: "w", perm: 0o600)

  jobs = modes.keys.map { |reference| QueueAdapterSmoke::OutboundClientJob.perform_later(reference) }
  QueueAdapterSmoke.assert(jobs.all?(&:successfully_enqueued?), "real outbound jobs not queued")
  QueueAdapterSmoke.assert(QueueAdapterSmoke::OutboundCall.count.zero?,
    "outbound Client executed before real worker was started")

  payloads = QueueAdapterSmoke.queue_payloads
  QueueAdapterSmoke.assert(payloads.size == modes.size, "unexpected queue size")
  payloads.each do |payload|
    args = ActiveJob::Arguments.deserialize(payload.fetch("arguments"))
    QueueAdapterSmoke.assert(args.size == 1 && modes.key?(args.first),
      "queue payload must contain only one non-secret reference ID")
    serialized = JSON.generate(payload)
    QueueAdapterSmoke.assert(!serialized.include?("Bearer") &&
      !serialized.include?("private-message-Part") &&
      modes.keys.none? { |reference| serialized.include?("worker-fake-token-#{reference}") },
      "queued job leaked credentials or raw Message Parts")
  end

  worker = QueueAdapterSmoke.start_worker(log)
  QueueAdapterSmoke.wait_until("separate worker outbound RPC outcomes") do
    QueueAdapterSmoke::OutboundCall.count == modes.size
  end
  QueueAdapterSmoke.wait_until("outbound queue fully drained") do
    QueueAdapterSmoke.outbound_queue_drained?
  end

  modes.each do |ref, mode|
    result = QueueAdapterSmoke::OutboundCall.find_by!(reference_id: ref)
    QueueAdapterSmoke.assert(result.worker_pid != Process.pid,
      "outbound Client ran in producer process, not worker")
    expected_outcome = case mode
    when "success" then "completed"
    when "timeout" then "uncertain_no_retry"
    when "wrong_origin" then "denied_before_rpc"
    end
    QueueAdapterSmoke.assert(result.outcome == expected_outcome,
      "unexpected #{ref} outcome: #{result.outcome}")
    if mode == "success"
      QueueAdapterSmoke.assert(result.remote_message_id == "server-message-#{ref}",
        "wrong remote Message ID after worker Client call")
    elsif mode == "timeout"
      QueueAdapterSmoke.assert(result.reason == "timeout", "ambiguous timeout reason missing")
    else
      QueueAdapterSmoke.assert(result.reason == "credential_origin_mismatch",
        "wrong-origin credential was not refused")
    end
  end

  servers.each do |server|
    entries = []
    entries << server.requests.pop until server.requests.empty?
    manifest_entry = manifest.fetch(modes.keys.find { |ref| manifest.fetch(ref).fetch(:origin) == server.origin })
    ref = modes.keys.find { |id| manifest.fetch(id).fetch(:origin) == server.origin }
    QueueAdapterSmoke.assert(entries.count { |r| r[:method] == "GET" } == 1,
      "missing original Card request")
    posts = entries.select { |r| r[:method] == "POST" }
    QueueAdapterSmoke.assert(posts.length == (manifest_entry.fetch(:mode) == "wrong_origin" ? 0 : 1),
      "duplicate, missing or wrong-origin outbound RPC")
    posts.each do |request|
      QueueAdapterSmoke.assert(request[:headers]["authorization"] ==
        "Bearer #{manifest_entry.fetch(:token)}", "cross-tenant bearer leaked")
      rpc = JSON.parse(request.fetch(:body))
      QueueAdapterSmoke.assert(rpc.dig("params", "message", "messageId") ==
        "message-#{ref}", "cross-tenant message ID")
    end
  end

  if ADAPTER == "sidekiq"
    require "sidekiq/api"
    QueueAdapterSmoke.assert(Sidekiq::RetrySet.new.size.zero?,
      "ambiguous SendMessage incorrectly entered automatic Sidekiq retry")
  else
    QueueAdapterSmoke.assert(SolidQueue::FailedExecution.count.zero?,
      "outbound Client failure unexpectedly retried or failed Solid Queue job")
  end

  # Only fake sentinels are used here. Both the queue and actual worker logs
  # must remain free of credential values and outbound Message payloads.
  log_body = File.read(log)
  modes.each_key do |reference|
    ["worker-fake-token-#{reference}", "private-message-Part-#{reference}"].each do |secret|
      QueueAdapterSmoke.assert(!log_body.include?(secret), "worker log leaked private Client data")
    end
  end
  puts "Step 29-5o #{ADAPTER} Rails #{Rails.version}: PASS (separate worker HTTPS, " \
    "isolated identities, serialized ID-only queue, one uncertain RPC, no auto retry)"
rescue StandardError
  warn File.read(log) if File.exist?(log)
  raise
ensure
  QueueAdapterSmoke.stop_worker(worker)
  servers.each(&:close)
  FileUtils.remove_entry(root) if File.directory?(root)
end
