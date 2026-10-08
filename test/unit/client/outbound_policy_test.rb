# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/a2a/rails/client/outbound_policy"

class ClientOutboundPolicyTest < Minitest::Test
  Policy = A2A::Rails::Client::OutboundPolicy
  Rejected = Policy::RejectedTarget

  def policy(origins: ["https://trusted.example"], records: ["8.8.8.8"], &resolver)
    Policy.new(
      allowed_origins: origins,
      resolver: resolver || ->(_host) { records }
    )
  end

  def test_valid_target_returns_immutable_pinned_connection_information
    target = policy.resolve!("https://trusted.example/a2a")
    assert_equal "https://trusted.example/a2a", target.url
    assert_equal "https://trusted.example", target.origin
    assert_equal "trusted.example", target.host
    assert_equal 443, target.port
    assert_equal ["8.8.8.8"], target.addresses
    assert_predicate target, :frozen?
    assert_predicate target.addresses, :frozen?
  end

  def test_valid_explicit_nondefault_port_requires_exact_allowlist
    target = policy(origins: ["https://trusted.example:8443"]).resolve!("https://trusted.example:8443/a2a")
    assert_equal 8443, target.port
    assert_equal "https://trusted.example:8443", target.origin
    assert_rejected(:unapproved_origin) do
      policy(origins: ["https://trusted.example"]).resolve!("https://trusted.example:8443/a2a")
    end
  end

  def test_path_is_not_assumed_and_card_and_rpc_hosts_must_each_be_allowed
    p = policy(origins: ["https://card.example", "https://rpc.example"])
    assert_equal "/custom/a2a", URI(p.resolve!("https://rpc.example/custom/a2a").url).path
    assert_equal "https://card.example", p.resolve!("https://card.example/.well-known/agent-card.json").origin
    assert_rejected(:unapproved_origin) do
      policy(origins: ["https://card.example"]).resolve!("https://rpc.example/custom/a2a")
    end
  end

  def test_no_unapproved_hostname_is_resolved
    called = false
    resolver = ->(_host) { called = true; ["8.8.8.8"] }
    assert_rejected(:unapproved_origin) do
      policy(origins: ["https://trusted.example"], &resolver).resolve!("https://evil.example/a2a")
    end
    refute called
  end

  def test_rejects_untrusted_urls_and_credentials
    {
      "http://trusted.example/a2a" => :invalid_url,
      "https://user:secret@trusted.example/a2a" => :invalid_url,
      "https://trusted.example/a2a?token=secret" => :invalid_url,
      "https://trusted.example/a2a#fragment" => :invalid_url,
      "https://127.0.0.1/a2a" => :invalid_host,
      "https://[::1]/a2a" => :invalid_host,
      "https://localhost/a2a" => :invalid_host,
      "https://trusted.example./a2a" => :invalid_host,
      "https://trusted.example/a2a/../secret" => :invalid_path,
      "https://trusted.example/%2e%2e/secret" => :invalid_path,
      " https://trusted.example/a2a" => :invalid_url,
      "javascript:alert(1)" => :invalid_url
    }.each do |url, reason|
      assert_rejected(reason) { policy.resolve!(url) }
    end
  end

  def test_approved_exact_origin_must_be_canonical_https
    [
      [],
      ["http://trusted.example"],
      ["https://trusted.example/a2a"],
      ["https://user:pass@trusted.example"],
      ["https://trusted.example?token=secret"],
      ["https://trusted.example", 123],
      ["https://*.example"]
    ].each do |origins|
      assert_raises(Rejected) { policy(origins: origins) }
    end
  end

  def test_rejects_all_observed_nonpublic_ipv4
    %w[
      0.0.0.0 10.1.2.3 100.64.1.1 127.0.0.1 169.254.169.254
      172.31.0.1 192.0.2.1 192.168.1.1 198.19.1.1
      198.51.100.1 203.0.113.1 224.0.0.1 240.0.0.1
    ].each do |addr|
      assert_rejected(:blocked_ip) { policy(records: [addr]).resolve!("https://trusted.example/a2a") }
    end
  end

  def test_a_public_result_is_not_allowed_if_any_answer_is_private
    assert_rejected(:blocked_ip) do
      policy(records: ["1.1.1.1", "169.254.169.254"]).resolve!("https://trusted.example/a2a")
    end
  end

  def test_rebind_is_rejected_even_after_previously_public_resolution
    answers = [["8.8.8.8"], ["169.254.169.254"]]
    p = policy { |_host| answers.shift || ["169.254.169.254"] }
    assert_equal ["8.8.8.8"], p.resolve!("https://trusted.example/a2a").addresses
    assert_rejected(:blocked_ip) { p.resolve!("https://trusted.example/a2a") }
  end

  def test_timeout_exception_is_not_hidden_by_dns_failure_wrapper
    p = policy { |_host| raise Timeout::Error, "DNS resolver private details" }
    error = assert_raises(Timeout::Error) { p.resolve!("https://trusted.example/a2a") }
    assert_kind_of Timeout::Error, error
  end

  def test_dns_failure_exception_does_not_retain_sensitive_cause
    p = policy { |_host| raise "private resolver query detail" }
    error = assert_raises(Rejected) { p.resolve!("https://trusted.example/a2a") }
    assert_equal :dns_failure, error.reason
    assert_nil error.cause
  end

  def test_public_dual_stack_resolves_only_pinned_ipv4_destinations
    target = policy(records: [
      "2600:1900:4240:200::", "34.143.75.2",
      "2600:1901:81d4:200::", "34.143.75.2", "34.143.74.2"
    ]).resolve!("https://trusted.example/a2a")
    assert_equal ["34.143.75.2", "34.143.74.2"], target.addresses
    assert_predicate target.addresses, :frozen?
    assert target.addresses.all? { |ip| IPAddr.new(ip).ipv4? }
  end

  def test_public_ipv6_only_cannot_be_dialed_without_ipv4
    assert_rejected(:unsupported_ip_family) do
      policy(records: ["2606:4700:4700::1111"]).resolve!("https://trusted.example/a2a")
    end
  end

  def test_rejects_any_unsafe_ipv6_even_alongside_public_ipv4
    [
      "::", "::1", "::ffff:169.254.169.254",
      "fe80::1", "fc00::1", "ff02::1",
      "64:ff9b::a9fe:a9fe", "2001::1",
      "2001:db8::1", "2002:c0a8:101::1",
      "3fff::1", "4000::1"
    ].each do |unsafe|
      assert_rejected(:blocked_ip) do
        policy(records: ["34.143.75.2", unsafe]).resolve!("https://trusted.example/a2a")
      end
    end
  end

  def test_rejects_unsafe_ipv4_even_alongside_public_ipv6
    assert_rejected(:blocked_ip) do
      policy(records: ["2600:1900:4240:200::", "34.143.75.2", "169.254.169.254"])
        .resolve!("https://trusted.example/a2a")
    end
  end

  def test_rejects_empty_invalid_or_failed_dns_results
    assert_rejected(:dns_failure) { policy(records: []).resolve!("https://trusted.example/a2a") }
    assert_rejected(:dns_failure) { policy(records: nil).resolve!("https://trusted.example/a2a") }
    assert_rejected(:invalid_dns_address) { policy(records: ["not-an-ip"]).resolve!("https://trusted.example/a2a") }
    assert_rejected(:dns_failure) do
      policy { |_host| raise Resolv::ResolvError }.resolve!("https://trusted.example/a2a")
    end
  end

  def test_same_host_different_port_fails
    assert_rejected(:unapproved_origin) do
      policy.resolve!("https://trusted.example:444/a2a")
    end
  end

  def test_errors_do_not_reflect_credentials_or_sensitive_url
    error = assert_raises(Rejected) do
      policy.resolve!("https://trusted.example/a2a?token=private-secret")
    end
    refute_includes error.message, "private-secret"
    assert_equal :invalid_url, error.reason
  end

  private

  def assert_rejected(reason)
    error = assert_raises(Rejected) { yield }
    assert_equal reason, error.reason
  end
end
