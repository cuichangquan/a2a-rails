# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "active_job"

class ClientPublicApiTest < Minitest::Test
  Client = A2A::Rails::Client

  # The job is run by several worker Threads with perform_now. It exercises
  # real ActiveJob execution callbacks but not a queue adapter/serialization.
  class ConcurrentClientJob < ActiveJob::Base
    def perform(client, message_id)
      client.send_message(message: {
        message_id: message_id, role: "ROLE_USER", parts: [{ text: "job payload" }]
      })
    end
  end

  class FakeResolver
    attr_accessor :reply, :failure, :card
    attr_reader :calls

    def initialize
      @calls = []
      @card = {
        "name" => "Test", "supportedInterfaces" => [{ "protocolBinding" => "JSONRPC",
                                                       "protocolVersion" => "1.0",
                                                       "url" => "https://agent.example/a2a" }],
        "securitySchemes" => { "customCamel" => { "secret_key" => false } }
      }
    end

    def discover
      raise failure if failure
      Struct.new(:card).new(card)
    end

    def rpc(method:, params:, id:)
      @calls << { method: method, params: params, id: id }
      raise failure if failure
      reply
    end
  end

  def setup
    @client = Client.new(
      agent_card_url: "https://agent.example/.well-known/agent-card.json",
      allowed_origins: ["https://agent.example"]
    )
    @resolver = FakeResolver.new
    # Internal seam for unit tests ONLY. The public constructor has no
    # resolver/policy/transport injection option.
    @client.instance_variable_set(:@resolver, @resolver)
  end

  def fixture(name)
    path = File.expand_path("../../contract/client_api/fixtures/vectors.json", __dir__)
    JSON.parse(File.read(path)).fetch("cases").find { |record| record["name"] == name }.fetch("wire")
  end

  def user_message(text: "Hello")
    { message_id: "m-123", role: "ROLE_USER", parts: [{ text: text }] }
  end

  def test_loaded_through_gem_entrypoint_without_server_agent
    assert_respond_to Client, :new
    assert_instance_of Client, @client
    assert_nil A2A::Rails::Configuration.new.agent
  end

  def test_send_result_task_and_rich_parts_follow_contract_vectors
    @resolver.reply = fixture("task-rich-parts")
    result = @client.send_message(message: user_message)
    assert_equal :task, result.kind
    assert_nil result.message
    assert_predicate result, :frozen?
    task = result.task
    assert_equal "remote-task-1", task.fetch(:id)
    assert_equal "ctx-1", task.fetch(:context_id)
    assert_equal "TASK_STATE_COMPLETED", task.dig(:status, :state)
    parts = task.fetch(:artifacts).fetch(0).fetch(:parts)
    assert_equal "text/plain", parts[0].fetch(:media_type)
    assert_equal "a-123", parts[1].dig(:data, "businessId")
    assert_equal "preserved", parts[1].dig(:data, "nested", "sameCase")
    assert_equal "SGVsbG8=", parts[2].fetch(:raw)
    assert_equal "opaque", task.dig(:metadata, "customKey")
    assert_predicate task, :frozen?
    assert_raises(FrozenError) { parts[1].fetch(:data)["businessId"] = "modified" }
    call = @resolver.calls.fetch(0)
    assert_equal "SendMessage", call[:method]
    assert_equal "m-123", call.dig(:params, "message", "messageId")
    assert_match(/\A[0-9a-f-]{36}\z/, call[:id])
  end

  def test_send_result_direct_message_and_output_configuration
    @resolver.reply = fixture("direct-message")
    r = @client.send_message(message: user_message,
      configuration: { accepted_output_modes: ["text/plain"], return_immediately: false },
      metadata: { auditTag: "keepCamelCase" })
    assert_equal :message, r.kind
    assert_nil r.task
    assert_equal "reply-1", r.message.fetch(:message_id)
    assert_equal "keepCamelCase", @resolver.calls.last.dig(:params, "metadata", "auditTag")
    assert_equal false, @resolver.calls.last.dig(:params, "configuration", "returnImmediately")
    assert_equal ["text/plain"], @resolver.calls.last.dig(:params, "configuration", "acceptedOutputModes")
  end

  def test_active_job_concurrent_perform_now_preserves_message_and_rpc_ids
    @resolver.reply = fixture("direct-message")
    ready = Queue.new
    go = Queue.new
    workers = 6.times.map do |index|
      Thread.new do
        ready << true
        go.pop
        ConcurrentClientJob.perform_now(@client, "job-message-#{index}")
      end
    end
    6.times { ready.pop }
    6.times { go << true }
    results = workers.map(&:value)

    assert results.all? { |result| result.kind == :message }
    assert_equal 6, @resolver.calls.length
    assert_equal (0...6).map { |index| "job-message-#{index}" }.sort,
      @resolver.calls.map { |call| call.dig(:params, "message", "messageId") }.sort
    assert_equal 6, @resolver.calls.map { |call| call.fetch(:id) }.uniq.length
    assert @resolver.calls.all? { |call| call[:method] == "SendMessage" }
  end

  def test_nonterminal_states_remain_visible
    @resolver.reply = fixture("task-input-required")
    result = @client.send_message(message: user_message)
    assert_equal "TASK_STATE_INPUT_REQUIRED", result.task.dig(:status, :state)
    assert_equal "status-1", result.task.dig(:status, :message, :message_id)

    @resolver.reply = fixture("task-auth-required")
    task = @client.get_task(id: "remote-task-3", history_length: 0)
    assert_equal "TASK_STATE_AUTH_REQUIRED", task.dig(:status, :state)
    assert_equal 0, @resolver.calls.last.dig(:params, "historyLength")
  end

  def test_list_tasks_returns_immutable_page_and_preserves_false_zero_and_empty_cursor
    @resolver.reply = fixture("list-tasks-terminal-page")
    page = @client.list_tasks(context_id: "context", page_size: 1, history_length: 0, include_artifacts: false)
    assert_instance_of Client::ListResult, page
    assert_predicate page, :frozen?
    assert_equal 1, page.page_size
    assert_equal 1, page.total_size
    assert_equal "", page.next_page_token
    assert_equal ["remote-task-1"], page.tasks.map { |task| task.fetch(:id) }
    assert_predicate page.tasks, :frozen?
    call = @resolver.calls.last
    assert_equal 0, call.dig(:params, "historyLength")
    assert_equal false, call.dig(:params, "includeArtifacts")
    assert_equal 1, call.dig(:params, "pageSize")
  end

  def test_cancel_task_preserves_remote_id
    @resolver.reply = { "id" => "t1", "status" => { "state" => "TASK_STATE_CANCELED" } }
    task = @client.cancel_task(id: "t1", metadata: { requestRef: "ref-1" })
    assert_equal "TASK_STATE_CANCELED", task.dig(:status, :state)
    assert_equal "ref-1", @resolver.calls.last.dig(:params, "metadata", "requestRef")
    assert_equal "CancelTask", @resolver.calls.last[:method]
  end

  def test_agent_card_has_only_normalized_protocol_keys_and_opaque_security_schemes
    card = @client.agent_card
    assert_equal "Test", card.fetch(:name)
    assert_equal "https://agent.example/a2a", card.fetch(:supported_interfaces)[0].fetch(:url)
    assert_equal "1.0", card.fetch(:supported_interfaces)[0].fetch(:protocol_version)
    assert_equal false, card.dig(:security_schemes, "customCamel", "secret_key")
    assert_raises(FrozenError) { card[:name] = "Changed" }
  end

  def test_send_response_must_be_exactly_one_of_task_or_message
    %w[invalid-send-result-both invalid-send-result-neither].each do |name|
      @resolver.reply = fixture(name)
      e = assert_raises(Client::InvalidResponseError) { @client.send_message(message: user_message) }
      assert_equal :invalid_send_result, e.reason
    end
  end

  def test_rejects_malformed_oneof_from_direct_remote_message
    [
      [{ "text" => "ok", "data" => { "secret" => "remote" } }],
      [{ "text" => "ok", "url" => "https://untrusted.example/file" }],
      [{ "mediaType" => "text/plain" }],
      ["malformed"],
      []
    ].each do |invalid_parts|
      @resolver.reply = fixture("direct-message")
      @resolver.reply.fetch("message")["parts"] = invalid_parts
      error = assert_raises(Client::InvalidResponseError) do
        @client.send_message(message: user_message)
      end
      assert_includes [:invalid_message, :invalid_message_part], error.reason
      refute_includes error.message, "secret"
    end
  end

  def test_message_requires_id_role_and_part_oneof
    [
      { role: "ROLE_USER", parts: [{ text: "ok" }] },
      { message_id: "m1", role: "ROLE_AGENT", parts: [{ text: "ok" }] },
      { message_id: "m1", role: "ROLE_USER", parts: [] },
      { message_id: "m1", role: "ROLE_USER", parts: [{ text: "ok", data: { x: 1 } }] },
      { message_id: "m1", role: "ROLE_USER", parts: [{ media_type: "text/plain" }] }
    ].each do |input|
      assert_raises(Client::InvalidInputError) { @client.send_message(message: input) }
    end
    assert_empty @resolver.calls
  end

  def test_codec_rejects_ambiguous_protocol_keys_in_request
    msg = user_message.merge("messageId" => "conflicting")
    assert_raises(Client::InvalidInputError) { @client.send_message(message: msg) }
    assert_empty @resolver.calls
  end

  def test_list_tasks_filter_validation
    @resolver.reply = fixture("list-tasks-terminal-page")
    [0, -1, 101, "5"].each do |size|
      assert_raises(Client::InvalidInputError) { @client.list_tasks(page_size: size) }
    end
    assert_raises(Client::InvalidInputError) { @client.list_tasks(include_artifacts: "false") }
    assert_empty @resolver.calls
  end

  def test_timeout_is_ambiguous_only_for_side_effecting_methods
    @resolver.failure = Client::PinnedHttpsTransport::DeadlineExceeded.new(:timeout)
    e = assert_raises(Client::TimeoutError) { @client.send_message(message: user_message) }
    assert e.may_have_executed
    e = assert_raises(Client::TimeoutError) { @client.get_task(id: "t1") }
    refute e.may_have_executed
    e = assert_raises(Client::TimeoutError) { @client.cancel_task(id: "t1") }
    assert e.may_have_executed
  end

  def test_timeout_does_not_retry_side_effecting_or_read_operations
    {
      send_message: { method: "SendMessage", may_have_executed: true },
      cancel_task: { method: "CancelTask", may_have_executed: true },
      get_task: { method: "GetTask", may_have_executed: false },
      list_tasks: { method: "ListTasks", may_have_executed: false }
    }.each do |operation, expected|
      @resolver.calls.clear
      @resolver.failure = Client::PinnedHttpsTransport::DeadlineExceeded.new(:timeout)
      error = assert_raises(Client::TimeoutError) do
        case operation
        when :send_message then @client.send_message(message: user_message)
        when :cancel_task then @client.cancel_task(id: "remote-task-id")
        when :get_task then @client.get_task(id: "remote-task-id")
        when :list_tasks then @client.list_tasks
        end
      end
      assert_equal operation, error.operation
      assert_equal expected.fetch(:may_have_executed), error.may_have_executed
      assert_nil error.cause
      assert_equal expected.fetch(:method), @resolver.calls.fetch(0).fetch(:method)
      assert_equal 1, @resolver.calls.length
      if operation == :send_message
        assert_equal "m-123", @resolver.calls.fetch(0).dig(:params, "message", "messageId")
      end
    end
  end

  def test_remote_error_is_typed_and_code_retained_without_original_message
    @resolver.failure = Client::AgentCardResolver::RemoteError.new(-32009)
    error = assert_raises(Client::RemoteError) { @client.get_task(id: "t1") }
    assert_equal(-32009, error.code)
    refute_includes error.message, "Bearer"
  end

  def test_auth_http_error_is_separate_from_other_http_status
    @resolver.failure = Client::PinnedHttpsTransport::HTTPError.new(403)
    error = assert_raises(Client::AuthenticationError) { @client.get_task(id: "t1") }
    assert_equal 403, error.status

    @resolver.failure = Client::PinnedHttpsTransport::HTTPError.new(503)
    assert_raises(Client::TransportError) { @client.get_task(id: "t1") }
  end

  def test_invalid_card_and_incompatible_interfaces_are_typed
    @resolver.failure = Client::AgentCardResolver::InvalidCard.new(:invalid_card_shape)
    assert_raises(Client::DiscoveryError) { @client.agent_card }

    @resolver.failure = Client::AgentCardResolver::UnsupportedInterface.new(:no_jsonrpc_v1_interface)
    assert_raises(Client::UnsupportedInterfaceError) { @client.agent_card }
  end

  def test_options_fail_closed_before_any_request
    assert_raises(Client::ConfigurationError) do
      Client.new(agent_card_url: "http://agent.example", allowed_origins: ["https://agent.example"])
    end
    assert_raises(Client::ConfigurationError) do
      Client.new(agent_card_url: "https://other.example/card", allowed_origins: ["https://agent.example"])
    end
    assert_raises(Client::ConfigurationError) do
      Client.new(agent_card_url: "https://agent.example/card", allowed_origins: ["https://agent.example"],
                 authorization: "Bearer token")
    end
    assert_raises(Client::ConfigurationError) do
      Client.new(agent_card_url: "https://agent.example/card", allowed_origins: ["https://agent.example"],
                 open_timeout: -1)
    end
  end

  def test_callback_origin_is_explicitly_bound
    client = Client.new(agent_card_url: "https://agent.example/card",
      allowed_origins: ["https://agent.example", "https://rpc.example"],
      authorization: -> { "Bearer test" }, credential_origin: "https://rpc.example")
    resolver = client.instance_variable_get(:@resolver)
    assert_equal "https://rpc.example", resolver.instance_variable_get(:@credential_origin)
  end
end
