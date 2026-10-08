# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/a2a/rails/client/pinned_https_transport"
require "openssl"
require "socket"
require "tempfile"
require "timeout"

class ClientPinnedHttpsTransportTest < Minitest::Test
  Transport = A2A::Rails::Client::PinnedHttpsTransport
  Policy = A2A::Rails::Client::OutboundPolicy

  class LoopbackTestPolicy
    attr_reader :resolved_urls

    def initialize
      @resolved_urls = []
    end

    # Explicit TEST-ONLY trusted policy: exercise real TLS + socket pinning
    # against local ephemeral SSL server. Never use this in a Rails app.
    def resolve!(url)
      @resolved_urls << url
      uri = URI(url)
      Policy::Target.new(
        url: url, host: uri.host, port: uri.port,
        origin: "https://#{uri.host}:#{uri.port}",
        addresses: ["127.0.0.1"].freeze
      ).freeze
    end
  end

  def setup
    @server_threads = []
    @servers = []
    @files = []
    @certificate, @private_key = self_signed_certificate("trusted.example")
    @ca_file = Tempfile.new("a2a-client-test-ca")
    @ca_file.write(@certificate.to_pem)
    @ca_file.flush
    @files << @ca_file
    @policy = LoopbackTestPolicy.new
  end

  def teardown
    @servers.each { |server| server.close rescue nil }
    @server_threads.each do |thread|
      thread.join(1)
      thread.kill if thread.alive?
      thread.join
    end
    @files.each { |file| file.close! rescue nil }
  end

  def test_real_https_get_pins_local_socket_ip_and_verifies_dns_hostname
    port, requests = tls_server(body: '{"name":"Test Agent"}')
    url = "https://trusted.example:#{port}/.well-known/agent-card.json"
    response = transport.get_json(url: url)
    assert_equal 200, response.status
    assert_equal({"name" => "Test Agent"}, response.json)
    assert_equal [url], @policy.resolved_urls
    assert_equal "/.well-known/agent-card.json", requests.pop.fetch(:path)
  end

  def test_real_https_post_includes_version_and_target_specific_credentials
    port, requests = tls_server(body: '{"result":{"task":{"id":"remote-id"}}}')
    url = "https://trusted.example:#{port}/remote/a2a"
    credentials = 0
    result = transport.post_json(url: url, json: {
      jsonrpc: "2.0", id: 1, method: "SendMessage",
      params: { message: { messageId: "m1", role: "ROLE_USER", parts: [{ text: "Hello" }] } }
    }, authorization: -> { credentials += 1; "Bearer fake-local-token" },
       credential_origin: "https://trusted.example:#{port}")

    assert_equal "remote-id", result.json.dig("result", "task", "id")
    assert_equal 1, credentials
    request = requests.pop
    assert_equal "/remote/a2a", request.fetch(:path)
    assert_equal "POST", request.fetch(:method)
    assert_equal "1.0", request.fetch(:headers).fetch("a2a-version")
    assert_equal "Bearer fake-local-token", request.fetch(:headers).fetch("authorization")
    assert_includes request.fetch(:body), '"SendMessage"'
    assert_match(/trusted.example/, request.fetch(:headers).fetch("host"))
  end

  def test_rejects_credentials_without_matching_approved_origin_before_callback
    called = false
    url = "https://trusted.example:8443/a2a"
    assert_error(:credential_origin_mismatch) do
      transport.post_json(url: url, json: {}, authorization: -> { called = true; "secret" },
                          credential_origin: "https://evil.example")
    end
    refute called
  end

  def test_rejects_unsafe_credentials_without_reflecting_secret
    assert_error(:invalid_credential) do
      transport.get_json(url: "https://trusted.example:443/card",
                         authorization: -> { "Bearer \r\nprivate-token" },
                         credential_origin: "https://trusted.example:443")
    end
  end

  def test_production_policy_rejects_loopback_dns_even_when_server_exists
    port, requests = tls_server(body: '{}')
    strict = Policy.new(
      allowed_origins: ["https://trusted.example:#{port}"],
      resolver: ->(_host) { ["127.0.0.1"] }
    )
    instance = Transport.new(policy: strict)
    assert_raises(Policy::RejectedTarget) do
      instance.get_json(url: "https://trusted.example:#{port}/card")
    end
    assert_empty requests
  end

  def test_real_https_redirect_is_blocked_not_followed
    port, requests = tls_server(status: "302 Found",
      headers: { "Location" => "http://169.254.169.254/latest/meta-data" },
      body: "redirect")
    assert_raises(Transport::RedirectBlocked) do
      transport.get_json(url: "https://trusted.example:#{port}/agent-card")
    end
    assert_equal "/agent-card", requests.pop.fetch(:path)
    assert_equal 1, @policy.resolved_urls.length
  end

  def test_real_https_body_is_bounded_during_streaming
    port, requests = tls_server(body: '{"too":"large payload"}')
    instance = transport(max_response_bytes: 8)
    assert_raises(Transport::ResponseTooLarge) do
      instance.get_json(url: "https://trusted.example:#{port}/a2a")
    end
    assert_equal "/a2a", requests.pop.fetch(:path)
  end

  def test_real_https_untrusted_certificate_is_rejected
    port, requests = tls_server(body: '{}')
    error = assert_raises(Transport::Error) do
      Transport.new(policy: @policy, total_timeout: 3).get_json(
        url: "https://trusted.example:#{port}/card"
      )
    end
    assert_equal :connection_failed, error.reason
    assert_empty requests
  end

  def test_real_https_certificate_hostname_mismatch_is_rejected
    other_certificate, other_key = self_signed_certificate("other.example")
    port, requests = tls_server(body: '{}', cert: other_certificate, key: other_key)
    error = assert_raises(Transport::Error) do
      transport.get_json(url: "https://trusted.example:#{port}/card")
    end
    assert_equal :connection_failed, error.reason
    assert_empty requests
  end

  def test_real_https_total_timeout_on_slow_response
    port, _requests = tls_server(body: '{}', delay: 0.5)
    error = assert_raises(Transport::DeadlineExceeded) do
      transport(read_timeout: 0.15, total_timeout: 0.2).get_json(
        url: "https://trusted.example:#{port}/slow"
      )
    end
    assert_equal :timeout, error.reason
  end

  def test_rejects_invalid_json_and_content_type
    port, _requests = tls_server(body: '{invalid}')
    assert_raises(Transport::InvalidResponse) do
      transport.get_json(url: "https://trusted.example:#{port}/a2a")
    end

    port2, _requests2 = tls_server(body: '<html></html>',
      headers: { "Content-Type" => "text/html" })
    error = assert_raises(Transport::InvalidResponse) do
      transport.get_json(url: "https://trusted.example:#{port2}/a2a")
    end
    assert_equal :invalid_content_type, error.reason
  end

  def test_never_uses_proxy_environment
    port, requests = tls_server(body: '{"ok":true}')
    # Do not change process-global ENV in a concurrent test: Net::HTTP is
    # explicitly constructed with p_addr=nil by the transport.
    assert_equal({ "ok" => true }, transport.get_json(
      url: "https://trusted.example:#{port}/a2a"
    ).json)
    assert_equal "/a2a", requests.pop.fetch(:path)
  end

  def test_size_and_timeout_limits_fail_before_connecting
    assert_error(:request_too_large) do
      transport(max_request_bytes: 4).post_json(url: "https://trusted.example/a2a", json: { big: "long" })
    end
    assert_error(:invalid_timeout) do
      transport(open_timeout: -1)
    end
    assert_error(:invalid_limit) do
      transport(max_json_nesting: 0)
    end
  end

  def test_http_errors_disclose_status_only
    port, requests = tls_server(status: "403 Forbidden", body: "SECRET PRIVATE BODY")
    error = assert_raises(Transport::HTTPError) do
      transport.get_json(url: "https://trusted.example:#{port}/card")
    end
    assert_equal 403, error.status
    refute_includes error.message, "SECRET"
    assert_equal "/card", requests.pop.fetch(:path)
  end

  private

  def transport(**options)
    Transport.new(policy: @policy, ca_file: @ca_file.path, **options)
  end

  def assert_error(reason)
    error = assert_raises(Transport::Error) { yield }
    assert_equal reason, error.reason
  end

  def self_signed_certificate(hostname)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(1_000_000) + 1
    subject = OpenSSL::X509::Name.parse("/CN=#{hostname}")
    cert.subject = subject
    cert.issuer = subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new
    extensions.subject_certificate = cert
    extensions.issuer_certificate = cert
    cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
    cert.add_extension(extensions.create_extension("keyUsage", "digitalSignature,keyEncipherment,keyCertSign", true))
    cert.add_extension(extensions.create_extension("subjectAltName", "DNS:#{hostname}", false))
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    [cert, key]
  end

  def tls_server(status: "200 OK", body: "{}", headers: {}, delay: 0,
                 cert: @certificate, key: @private_key)
    socket = TCPServer.new("127.0.0.1", 0)
    port = socket.addr[1]
    @servers << socket
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = cert
    ctx.key = key
    server = OpenSSL::SSL::SSLServer.new(socket, ctx)
    requests = Queue.new

    thread = Thread.new do
      peer = nil
      begin
        peer = server.accept
        first = peer.gets
        unless first.nil?
          method, path, = first.strip.split(" ", 3)
          header_lines = []
          while (line = peer.gets) && line != "\r\n"
            header_lines << line
          end
          parsed_headers = header_lines.map { |line| line.split(":", 2).map(&:strip) }
            .to_h.transform_keys(&:downcase)
          length = parsed_headers.fetch("content-length", "0").to_i
          request_body = length.zero? ? "" : peer.read(length)
          requests << { method: method, path: path, headers: parsed_headers, body: request_body }

          sleep(delay) if delay.positive?
          response_headers = { "Content-Type" => "application/json",
                               "Connection" => "close", "Content-Length" => body.bytesize.to_s }.merge(headers)
          peer.write "HTTP/1.1 #{status}\r\n" +
            response_headers.map { |name, value| "#{name}: #{value}\r\n" }.join +
            "\r\n" + body
        end
      rescue OpenSSL::SSL::SSLError, IOError, Errno::EPIPE, Errno::ECONNRESET
        # Expected for certificate rejection, early body caps and test cleanup.
      ensure
        peer&.close rescue nil
      end
    end
    @server_threads << thread
    [port, requests]
  end
end
