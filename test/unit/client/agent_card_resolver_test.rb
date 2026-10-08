# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/a2a/rails/client/agent_card_resolver"

class ClientAgentCardResolverTest < Minitest::Test
  Resolver = A2A::Rails::Client::AgentCardResolver
  Policy = A2A::Rails::Client::OutboundPolicy
  Transport = A2A::Rails::Client::PinnedHttpsTransport

  class FakeTransport
    attr_accessor :card, :response
    attr_reader :gets, :posts

    def initialize(card)
      @card = card
      @gets = []
      @posts = []
    end

    def get_json(**args)
      @gets << args
      Transport::Response.new(status: 200, json: Marshal.load(Marshal.dump(card)))
    end

    def post_json(**args)
      @posts << args
      reply = response || { "jsonrpc" => "2.0", "id" => 12, "result" => { "id" => "t1" } }
      Transport::Response.new(status: 200, json: Marshal.load(Marshal.dump(reply)))
    end
  end

  def card(interfaces = [{ "url" => "https://api.example/custom/a2a",
                           "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" }])
    {
      "name" => "Example", "description" => "Example Agent",
      "version" => "1.0", "capabilities" => { "streaming" => false },
      "defaultInputModes" => ["text/plain"], "defaultOutputModes" => ["text/plain"],
      "skills" => [{ "id" => "echo", "name" => "Echo", "tags" => ["echo"] }],
      "supportedInterfaces" => interfaces
    }
  end

  def setup
    @transport = FakeTransport.new(card)
    @policy = Policy.new(
      allowed_origins: ["https://card.example", "https://api.example"],
      resolver: ->(_hostname) { ["8.8.8.8"] }
    )
  end

  def resolver(**options)
    Resolver.new(agent_card_url: "https://card.example/.well-known/agent-card.json",
                 policy: @policy, transport: @transport, **options)
  end

  def test_uses_first_compatible_interface_not_guessed_path
    @transport.card = card([
      { "url" => "https://legacy.example/v03", "protocolBinding" => "JSONRPC", "protocolVersion" => "0.3" },
      { "url" => "https://grpc.example/service", "protocolBinding" => "GRPC", "protocolVersion" => "1.0" },
      { "url" => "https://api.example/agent/jsonrpc", "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" },
      { "url" => "https://api.example/other", "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" }
    ])
    selected = resolver.discover
    assert_equal "https://api.example/agent/jsonrpc", selected.interface.url
    assert_nil selected.interface.tenant
    assert_predicate selected.card, :frozen?
    assert_predicate selected.card["skills"], :frozen?
    assert_equal "https://card.example/.well-known/agent-card.json", @transport.gets.first.fetch(:url)
  end

  def test_unsupported_bindings_and_old_versions_are_rejected
    @transport.card = card([
      { "url" => "https://api.example/rest", "protocolBinding" => "HTTP+JSON", "protocolVersion" => "1.0" },
      { "url" => "https://api.example/old", "protocolBinding" => "JSONRPC", "protocolVersion" => "0.3" }
    ])
    assert_raises(Resolver::UnsupportedInterface) { resolver.discover }
    assert_empty @transport.posts
  end

  def test_card_selected_url_must_be_approved
    @transport.card["supportedInterfaces"][0]["url"] = "https://unlisted.example/a2a"
    assert_raises(Policy::RejectedTarget) { resolver.discover }
    assert_empty @transport.posts
  end

  def test_rejects_invalid_card_shapes
    [nil, {}, card([]), card.tap { |v| v.delete("name") },
     card.tap { |v| v["skills"] = [] },
     card.tap { |v| v["capabilities"] = [] }].each do |value|
      @transport.card = value
      assert_raises(Resolver::InvalidCard) { resolver.discover }
    end
  end

  def test_rejects_incompatible_tenant_type
    @transport.card["supportedInterfaces"][0]["tenant"] = 24
    assert_raises(Resolver::InvalidCard) { resolver.discover }
  end

  def test_injects_tenant_on_every_operation
    @transport.card["supportedInterfaces"][0]["tenant"] = "billing"
    %w[SendMessage GetTask ListTasks CancelTask].each do |method|
      request_params = { "id" => "abc" }
      result = resolver.rpc(method: method, params: request_params, id: 12)
      assert_equal({ "id" => "t1" }, result)
      assert_equal "billing", @transport.posts.last.dig(:json, "params", "tenant")
      assert_equal "2.0", @transport.posts.last.dig(:json, "jsonrpc")
      assert_equal method, @transport.posts.last.dig(:json, "method")
      assert_equal({ "id" => "abc" }, request_params)
    end
  end

  def test_declared_empty_tenant_is_preserved_and_undeclared_tenant_omitted
    resolver.rpc(method: "GetTask", params: { "id" => "t1" }, id: 12)
    refute @transport.posts.last.fetch(:json).fetch("params").key?("tenant")

    @transport.card["supportedInterfaces"][0]["tenant"] = ""
    resolver.rpc(method: "GetTask", params: { "id" => "t1" }, id: 12)
    assert_equal "", @transport.posts.last.fetch(:json).fetch("params").fetch("tenant")
  end

  def test_mixed_public_and_private_dns_for_declared_rpc_is_rejected
    policy = Policy.new(
      allowed_origins: ["https://card.example", "https://api.example"],
      resolver: ->(host) { host == "api.example" ? ["1.1.1.1", "169.254.169.254"] : ["1.1.1.1"] }
    )
    assert_raises(Policy::RejectedTarget) { resolver(policy: policy).discover }
    assert_empty @transport.posts
  end

  def test_rejects_invalid_json_rpc_envelope
    [
      {},
      { "id" => 12, "result" => {} },
      { "jsonrpc" => "2.0", "id" => 24, "result" => {} },
      { "jsonrpc" => "2.0", "id" => 12, "result" => {}, "error" => { "code" => -32600 } },
      { "jsonrpc" => "2.0", "id" => 12, "result" => [] }
    ].each do |bad|
      @transport.response = bad
      assert_raises(Resolver::InvalidRPC) { resolver.rpc(method: "GetTask", params: { "id" => "t1" }, id: 12) }
    end
  end

  def test_preserves_remote_error_code_but_not_untrusted_message
    @transport.response = {
      "jsonrpc" => "2.0", "id" => 12,
      "error" => { "code" => -32009, "message" => "untrusted diagnostic", "data" => { "detail" => "private" } }
    }
    error = assert_raises(Resolver::RemoteError) { resolver.rpc(method: "GetTask", params: { "id" => "t1" }, id: 12) }
    assert_equal(-32009, error.code)
    refute_includes error.message, "untrusted diagnostic"
  end

  def test_wire_result_is_deeply_frozen_without_changing_json_fields
    @transport.response = {
      "jsonrpc" => "2.0", "id" => 12,
      "result" => { "message" => { "parts" => [{ "data" => { "camelKey" => true } }] } }
    }
    value = resolver.rpc(method: "SendMessage", params: {}, id: 12)
    assert_equal true, value.dig("message", "parts", 0, "data", "camelKey")
    assert_raises(FrozenError) { value["message"]["parts"][0]["data"]["camelKey"] = false }
  end

  def test_auth_callbacks_use_independently_scoped_origins
    card_auth = -> { "Bearer card" }
    rpc_auth = -> { "Bearer rpc" }
    resolver(card_authorization: card_auth, card_credential_origin: "https://card.example",
             authorization: rpc_auth, credential_origin: "https://api.example")
      .rpc(method: "GetTask", params: { "id" => "t1" }, id: 12)
    assert_same card_auth, @transport.gets.last.fetch(:authorization)
    assert_equal "https://card.example", @transport.gets.last.fetch(:credential_origin)
    assert_same rpc_auth, @transport.posts.last.fetch(:authorization)
    assert_equal "https://api.example", @transport.posts.last.fetch(:credential_origin)
  end

  def test_tenant_override_and_unrecognized_rpc_are_rejected_before_discovery
    assert_raises(Resolver::InvalidRPC) do
      resolver.rpc(method: "GetTask", params: { "tenant" => "other" }, id: 12)
    end
    assert_raises(Resolver::InvalidRPC) do
      resolver.rpc(method: "UnsupportedOperation", params: {}, id: 12)
    end
    assert_empty @transport.gets
  end
end
