# frozen_string_literal: true

# Step 29-5c controlled public IPv4 DNS / public CA proof, separate from the
# normal Rails Client smoke. This DOES NOT override Client DNS, TLS or policy.
# Never run against arbitrary third-party hosts.
abort "Controlled endpoint approval is required" unless
  ENV["A2A_PUBLIC_EGRESS_APPROVED"] == "controlled-endpoint-no-auth"

require "a2a-rails"
require "openssl"
require "socket"
require "timeout"
require "time"

def setting(name)
  value = ENV[name]
  abort "Missing controlled egress configuration: #{name}" unless
    value.is_a?(String) && !value.strip.empty? && value == value.strip
  value
end

card_url = setting("A2A_PUBLIC_CARD_URL")
rpc_url = setting("A2A_PUBLIC_EXPECTED_RPC_URL")
origins = setting("A2A_PUBLIC_ALLOWED_ORIGINS").split(",", -1)
abort "Invalid origin allowlist" unless origins.all? { |item| item == item.strip && !item.empty? }

# This is the same strict, non-injected DNS/origin policy used by Client.
policy = A2A::Rails::Client::OutboundPolicy.new(allowed_origins: origins)
[card_url, rpc_url].each { |url| policy.validate_url!(url) }

[card_url, rpc_url].uniq.each do |url|
  begin
    Timeout.timeout(8) do
      target = policy.resolve!(url)
      ip = target.addresses.first
      tcp = nil
      ssl = nil
      begin
        tcp = Socket.tcp(ip, target.port, connect_timeout: 3)
        actual_ip = tcp.remote_address.ip_address
        abort "Pinned socket destination changed" unless actual_ip == ip

        store = OpenSSL::X509::Store.new
        store.set_default_paths
        context = OpenSSL::SSL::SSLContext.new
        context.verify_mode = OpenSSL::SSL::VERIFY_PEER
        context.verify_hostname = true
        context.cert_store = store

        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.sync_close = true
        ssl.hostname = target.host # Original DNS name for SNI and peer check.
        ssl.connect
        ssl.post_connection_check(target.host)
        cert = ssl.peer_cert
        abort "Missing verified peer certificate" unless cert

        issuer = cert.issuer.to_s.gsub(/[^\x20-\x7e]/, "?")[0, 200]
        puts "PASS: public IPv4 DNS and public-CA TLS peer verified"
        puts "Origin: #{target.origin} / IP: #{actual_ip}"
        puts "TLS issuer: #{issuer}"
        puts "TLS notAfter (UTC): #{cert.not_after.utc.iso8601}"
        puts "TLS cert SHA256: #{OpenSSL::Digest::SHA256.hexdigest(cert.to_der)}"
      ensure
        ssl&.close rescue nil
        tcp&.close rescue nil
      end
    end
  rescue StandardError
    # Avoid embedding remote hostname, TLS exception details or untrusted data
    # in a sanitized CI failure log. The operator can inspect network telemetry.
    abort "FAIL: controlled public DNS/TLS preflight rejected (details suppressed)"
  end
end

puts "PASS: preflight sockets use approved pinned IPv4, original SNI, system CA"
puts "NOTE: preflight socket IP is NOT proof of the later Rails Client dialed IP."
