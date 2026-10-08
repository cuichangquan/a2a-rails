# frozen_string_literal: true

# Step 26-2: host-owned, deterministic JWT-HS256 fixture, run in an isolated
# production Rails process against the exact locally BUILT/INSTALLED Gem.
# It is NOT a Gem identity provider or a production JWT verifier.
require "base64"
require "json"
require "logger"
require "openssl"
require "securerandom"
require "set"
require "stringio"
require "rack/mock"
require "action_controller/railtie"
require "a2a-rails"

module Step262SecuritySmoke
  ISSUER = "https://identity.fixture.invalid"
  AUDIENCE = "a2a-rails-ci"
  SECRET = "step-26-2-fixture-hmac-key-not-for-production-use".ljust(64, "x")
  LEAK_MARKER = "fixture-private-key-never-echo-this-26-2"
  SIGNING_KEYS = { "test-primary" => SECRET }.freeze

  class TokenService
    def initialize
      @revoked = Set.new
    end

    def revoke!(jti)
      @revoked.add(jti)
    end

    def encode(payload, header: { "alg" => "HS256", "typ" => "JWT", "kid" => "test-primary" },
      secret: SECRET)
      signing_input = [header, payload].map do |value|
        Base64.urlsafe_encode64(JSON.generate(value), padding: false)
      end.join(".")
      signature = OpenSSL::HMAC.digest("SHA256", secret, signing_input)
      "#{signing_input}.#{Base64.urlsafe_encode64(signature, padding: false)}"
    end

    def issue(tenant:, subject:, at: Time.now.to_i, jti: SecureRandom.uuid, **overrides)
      encode({
        "iss" => ISSUER,
        "aud" => AUDIENCE,
        "sub" => subject,
        "tid" => tenant,
        "iat" => at,
        "nbf" => at - 5,
        "exp" => at + 600,
        "jti" => jti
      }.merge(overrides.transform_keys(&:to_s)))
    end

    def verify(authorization)
      return nil unless authorization.is_a?(String) && authorization.start_with?("Bearer ")
      token = authorization.delete_prefix("Bearer ")
      segments = token.split(".", -1)
      return nil unless segments.length == 3
      head, payload, signature = segments
      header = JSON.parse(Base64.urlsafe_decode64(head))
      claims = JSON.parse(Base64.urlsafe_decode64(payload))
      return nil unless header.is_a?(Hash) && claims.is_a?(Hash)
      return nil unless header["alg"] == "HS256" && header["typ"] == "JWT"
      key = SIGNING_KEYS[header["kid"]]
      return nil unless key

      expected = OpenSSL::HMAC.digest("SHA256", key, "#{head}.#{payload}")
      actual = Base64.urlsafe_decode64(signature)
      return nil unless actual.bytesize == expected.bytesize
      return nil unless OpenSSL.fixed_length_secure_compare(expected, actual)

      now = Time.now.to_i
      return nil unless claims["iss"] == ISSUER && claims["aud"] == AUDIENCE
      return nil unless claims["exp"].is_a?(Integer) && now < claims["exp"]
      return nil unless claims["nbf"].is_a?(Integer) && now >= claims["nbf"]
      return nil unless claims["iat"].is_a?(Integer) && now >= claims["iat"] - 30
      return nil unless claims["jti"].is_a?(String) && !claims["jti"].empty?
      return nil if @revoked.include?(claims["jti"])
      return nil unless [claims["tid"], claims["sub"]].all? do |s|
        s.is_a?(String) && s.match?(/\A[a-zA-Z0-9_-]{1,40}\z/)
      end

      "#{claims.fetch("tid")}:#{claims.fetch("sub")}"
    rescue ArgumentError, JSON::ParserError, TypeError
      nil
    end
  end

  class Handler
    class << self
      attr_accessor :calls, :last_principal
    end
    self.calls = 0

    def self.call(message:, context:)
      self.calls += 1
      self.last_principal = context.fetch(:principal_id)
      "Echo: #{message.fetch(:parts).first.fetch(:text)}"
    end
  end

  class Agent < A2A::Rails::Agent
    name "Step 26-2 token and isolation fixture"
    description "CI fixture, not a production agent"
    version "1.0"
    skill :reply, description: "Reply", tags: %w[security], handler: Handler
  end

  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "step26-2-rails-smoke-test-only-secret-key-base"
    config.hosts.clear
    config.logger = Logger.new(nil)
    config.action_dispatch.show_exceptions = :none
  end

  module_function

  def assert(condition, message)
    raise message unless condition
  end

  def rpc(auth, method, params = {}, env_overrides: {}, **keyword_params)
    params = params.merge(keyword_params)
    body = JSON.generate(
      "jsonrpc" => "2.0", "id" => SecureRandom.uuid,
      "method" => method, "params" => params
    )
    request_env = {
      "CONTENT_TYPE" => "application/json",
      "HTTP_A2A_VERSION" => "1.0",
      "HTTP_HOST" => "localhost",
      input: body
    }.merge(env_overrides)
    request_env["HTTP_AUTHORIZATION"] = "Bearer #{auth}" if auth
    Rack::MockRequest.new(Application.instance).post("/a2a", request_env)
  end

  def result(response)
    assert(response.status == 200, "expected RPC HTTP 200; received #{response.status}")
    parsed = JSON.parse(response.body)
    assert(parsed.key?("result") && !parsed.key?("error"), "RPC did not succeed: #{parsed.inspect}")
    parsed.fetch("result")
  end

  def error_code(response, expected)
    assert(response.status == 200, "expected JSON-RPC error via HTTP 200, got #{response.status}")
    actual = JSON.parse(response.body).dig("error", "code")
    assert(actual == expected, "expected RPC error #{expected}, got #{actual.inspect}")
  end

  def message(text, task_id: nil)
    data = {
      "messageId" => SecureRandom.uuid,
      "role" => "ROLE_USER",
      "contextId" => "shared-secure-context",
      "parts" => [{ "text" => text }]
    }
    data["taskId"] = task_id if task_id
    { "message" => data }
  end

  def send_task(token, text)
    task = result(rpc(token, "SendMessage", message(text))).fetch("task")
    assert(task.dig("status", "state") == "TASK_STATE_COMPLETED", "valid Task not completed")
    task
  end

  def assert_rejected(response, status, label)
    assert(response.status == status, "#{label} expected HTTP #{status}, got #{response.status}")
    parsed = JSON.parse(response.body)
    expected = { 401 => "Unauthorized", 403 => "Forbidden", 500 => "Authentication unavailable" }
    assert(parsed == { "error" => expected.fetch(status) }, "#{label} unsafe HTTP response")
    assert(response["Cache-Control"].to_s.include?("no-store"), "#{label} missing no-store")
    if status == 401
      assert(response["WWW-Authenticate"] == 'Bearer realm="a2a"',
        "#{label} missing Bearer challenge")
    end
  end

  def run
    assert(::Rails.env.production?, "must execute as RAILS_ENV=production")
    spec = Gem.loaded_specs.fetch("a2a-rails")
    assert(spec.version.to_s == ENV.fetch("A2A_RAILS_EXPECTED_VERSION"), "wrong candidate")
    source = File.realpath(ENV.fetch("A2A_RAILS_SOURCE_ROOT"))
    assert(!File.realpath(spec.full_gem_path).start_with?(source + File::SEPARATOR),
      "security smoke accidentally loaded source checkout")

    log_io = StringIO.new
    cfg = A2A::Rails::Configuration.new
    cfg.agent = "Step262SecuritySmoke::Agent"
    cfg.public_base_url = "https://agents.example.test"
    cfg.logger = Logger.new(log_io)
    A2A::Rails.instance_variable_set(:@configuration, cfg)
    A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new)
    Application.initialize!

    card = Rack::MockRequest.new(Application.instance).get("/.well-known/agent-card.json")
    assert(card.status == 503 && JSON.parse(card.body).fetch("error") == "Agent Card unavailable",
      "unauthenticated production Agent Card did not fail closed")
    assert_rejected(rpc(nil, "SendMessage", message("blocked")), 401, "unconfigured production host")
    assert(Handler.calls.zero?, "unconfigured host reached Handler")

    tokens = TokenService.new
    cfg.authenticate_request = lambda do |req|
      auth = req.get_header("HTTP_AUTHORIZATION")
      raise A2A::Rails::Authentication::Forbidden if auth == "Bearer policy-denied"
      raise LEAK_MARKER if auth == "Bearer verifier-crash"
      tokens.verify(auth)
    end

    # Verifier with no advertised security metadata is inconsistent and fails closed.
    card = Rack::MockRequest.new(Application.instance).get("/.well-known/agent-card.json")
    assert(card.status == 503, "misconfigured Agent Card must fail closed")
    assert_rejected(rpc("bogus", "SendMessage", message("blocked")), 500, "missing card metadata")
    assert(Handler.calls.zero?, "inconsistent metadata reached Handler")

    cfg.security_schemes = {
      "bearer" => { "httpAuthSecurityScheme" => {
        "scheme" => "Bearer", "bearerFormat" => "JWT"
      } }
    }
    cfg.security_requirements = [{ "schemes" => { "bearer" => { "list" => [] } } }]

    card = Rack::MockRequest.new(Application.instance).get("/.well-known/agent-card.json")
    assert(card.status == 200 && card["Cache-Control"].to_s.include?("no-store"),
      "verified Agent Card unavailable or cacheable")
    advertised = JSON.parse(card.body)
    assert(advertised.dig("securitySchemes", "bearer", "httpAuthSecurityScheme", "scheme") == "Bearer",
      "Agent Card authentication profile mismatch")
    assert(advertised.fetch("securityRequirements") ==
      [{ "schemes" => { "bearer" => { "list" => [] } } }],
      "Agent Card requirement mismatch")
    assert(advertised.fetch("supportedInterfaces").first.fetch("url") ==
      "https://agents.example.test/a2a", "Agent Card public URL mismatch")

    now = Time.now.to_i
    valid_a = tokens.issue(tenant: "tenant-A", subject: "user-1", at: now)
    valid_b = tokens.issue(tenant: "tenant-B", subject: "user-1", at: now)
    revoked = tokens.issue(tenant: "tenant-A", subject: "revoked", at: now, jti: "revoked-jti")
    tokens.revoke!("revoked-jti")

    forged = valid_a.dup
    parts = forged.split(".")
    parts[1] = Base64.urlsafe_encode64(JSON.generate({
      "iss" => ISSUER, "aud" => AUDIENCE, "tid" => "tenant-B", "sub" => "user-1",
      "nbf" => now - 5, "exp" => now + 600, "iat" => now, "jti" => "forged"
    }), padding: false)
    forged = parts.join(".")

    rejected_tokens = {
      "missing bearer" => nil,
      "garbage" => "not-a-token",
      "modified claims with old signature" => forged,
      "wrong signing key" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now).then { |t| t.split(".").then { |p| tokens.encode(
          JSON.parse(Base64.urlsafe_decode64(p[1])), secret: "wrong-fixture-signing-key"
        ) } },
      "expired" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, exp: now - 1),
      "not yet valid" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, nbf: now + 3600),
      "future issued-at" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, iat: now + 3600),
      "wrong issuer" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, iss: "https://attacker.invalid"),
      "wrong audience" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, aud: "unrelated-service"),
      "revoked" => revoked,
      "missing subject" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, sub: nil),
      "missing tenant" => tokens.issue(tenant: "tenant-A", subject: "user-1",
        at: now, tid: nil),
      "unknown key id" => tokens.issue(tenant: "tenant-A", subject: "user-1", at: now)
        .then { |t| tokens.encode(JSON.parse(Base64.urlsafe_decode64(t.split(".")[1])),
          header: { "alg" => "HS256", "typ" => "JWT", "kid" => "unknown" }) },
      "alg none" => tokens.issue(tenant: "tenant-A", subject: "user-1", at: now)
        .then { |t| tokens.encode(JSON.parse(Base64.urlsafe_decode64(t.split(".")[1])),
          header: { "alg" => "none", "typ" => "JWT", "kid" => "test-primary" }) }
    }

    rejected_tokens.each do |reason, token|
      assert_rejected(rpc(token, "SendMessage", message("blocked")),
        401, reason)
    end
    assert_rejected(rpc("policy-denied", "SendMessage", message("blocked")), 403,
      "host access policy")
    assert_rejected(rpc("verifier-crash", "SendMessage", message("blocked")), 500,
      "exception sanitization")
    assert(Handler.calls.zero?, "rejected credentials reached Handler")
    assert(A2A::Rails.runtime.task_store.list(principal_id: "tenant-A:user-1")[:total_size] == 0,
      "rejected credentials created a Task")

    alice1 = send_task(valid_a, "alice-1")
    alice2 = send_task(valid_a, "alice-2")
    bob1 = send_task(valid_b, "bob-1")
    assert(Handler.calls == 3 && Handler.last_principal == "tenant-B:user-1",
      "valid verified principal was not passed to Handler")
    assert(![alice1, alice2, bob1].any? { |task| JSON.generate(task).include?("tenant-") },
      "private owner identity leaked into Task response")
    assert(result(rpc(valid_a, "GetTask", "id" => alice1.fetch("id"))).fetch("id") ==
      alice1.fetch("id"), "owner cannot retrieve Task")
    error_code(rpc(valid_b, "GetTask", "id" => alice1.fetch("id")), -32_001)
    error_code(rpc(valid_a, "GetTask", "id" => bob1.fetch("id")), -32_001)

    list_a = result(rpc(valid_a, "ListTasks",
      "contextId" => "shared-secure-context", "pageSize" => 1))
    assert(list_a.fetch("totalSize") == 2 && list_a.fetch("tasks").length == 1,
      "wrong tenant A ListTasks size")
    cursor = list_a.fetch("nextPageToken")
    assert(cursor.is_a?(String) && !cursor.empty?, "missing page cursor")
    next_a = result(rpc(valid_a, "ListTasks", "contextId" => "shared-secure-context",
      "pageSize" => 1, "pageToken" => cursor))
    assert((list_a.fetch("tasks") + next_a.fetch("tasks")).map { |t| t.fetch("id") }.sort ==
      [alice1.fetch("id"), alice2.fetch("id")].sort, "owner pagination incorrect")

    list_b = result(rpc(valid_b, "ListTasks", "contextId" => "shared-secure-context"))
    assert(list_b.fetch("totalSize") == 1 && list_b.fetch("tasks").first.fetch("id") ==
      bob1.fetch("id"), "cross-tenant ListTasks count/items leaked")
    error_code(rpc(valid_b, "ListTasks", "contextId" => "shared-secure-context",
      "pageSize" => 1, "pageToken" => cursor), -32_602)
    error_code(rpc(valid_a, "ListTasks", "contextId" => "different-filter",
      "pageSize" => 1, "pageToken" => cursor), -32_602)
    error_code(rpc(valid_a, "ListTasks", "contextId" => "shared-secure-context",
      "pageSize" => 2, "pageToken" => cursor), -32_602)
    error_code(rpc(valid_b, "SendMessage",
      message("foreign continuation", task_id: alice1.fetch("id"))), -32_001)

    store = A2A::Rails.runtime.task_store
    pending = A2A::Rails::Task::Lifecycle.new(
      store: store, principal_id: "tenant-A:user-1"
    ).create(message: {
      message_id: SecureRandom.uuid, role: :user, parts: [{ text: "pending" }]
    })
    error_code(rpc(valid_b, "CancelTask", "id" => pending.fetch(:id)), -32_001)
    assert(result(rpc(valid_a, "CancelTask",
      "id" => pending.fetch(:id))).dig("status", "state") == "TASK_STATE_CANCELED",
      "owner cannot cancel pending Task")

    # Revocation must be enforced at every new HTTP request, not at issuance.
    tokens.revoke!(JSON.parse(Base64.urlsafe_decode64(valid_a.split(".")[1])).fetch("jti"))
    assert_rejected(rpc(valid_a, "GetTask", "id" => alice1.fetch("id")),
      401, "revoked-after-previously-valid")
    assert(Handler.calls == 3, "Handler invoked during authorization regression")

    cfg.security_requirements = nil
    inconsistent = Rack::MockRequest.new(Application.instance).get("/.well-known/agent-card.json")
    assert(inconsistent.status == 503, "invalid Agent Card must fail closed")
    assert_rejected(rpc(valid_b, "SendMessage", message("misconfigured")), 500,
      "mismatched verifier/card")
    assert(Handler.calls == 3, "misconfiguration reached Handler")

    combined = [log_io.string, card.body, inconsistent.body]
    assert(combined.none? { |part| part.include?(LEAK_MARKER) || part.include?(SECRET) ||
      part.include?(valid_a) || part.include?(valid_b) },
      "sensitive authentication fixture value leaked to log or card")
    puts "Step 26-2 installed-Gem auth & isolation: PASS (#{rejected_tokens.length} invalid-token classes)"
  end
end

Step262SecuritySmoke.run
