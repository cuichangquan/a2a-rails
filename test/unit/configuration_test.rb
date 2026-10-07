# frozen_string_literal: true

require_relative "../test_helper"

class ConfigurationTest < Minitest::Test
  module Fixtures
    class RegisteredAgent < A2A::Rails::Agent
      name "Registered Agent"
      description "Configuration fixture"
      version "1.0"
      skill :reply, description: "Reply", tags: %w[test], handler: ->(message:, context:) { [message, context] }
    end
  end

  def test_configuration_is_incomplete_without_resolving_at_initialization
    config = A2A::Rails::Configuration.new

    assert_nil config.agent
    assert_nil config.public_base_url
    assert_nil config.logger
    assert_raises(A2A::Rails::ConfigurationError) { config.resolve_agent }
  end

  def test_resolves_registered_agent_from_class_name_string
    config = A2A::Rails::Configuration.new
    config.agent = "ConfigurationTest::Fixtures::RegisteredAgent"

    assert_same Fixtures::RegisteredAgent, config.resolve_agent
  end

  def test_missing_or_non_agent_constant_is_a_configuration_error
    config = A2A::Rails::Configuration.new
    config.agent = "ConfigurationTest::Fixtures::MissingAgent"
    assert_raises(A2A::Rails::ConfigurationError) { config.resolve_agent }

    config.agent = "String"
    error = assert_raises(A2A::Rails::ConfigurationError) { config.resolve_agent }
    assert_match(/inherit/, error.message)
  end

  def test_public_base_url_is_normalized_lazily
    config = A2A::Rails::Configuration.new
    config.agent = "ConfigurationTest::Fixtures::RegisteredAgent"
    config.public_base_url = " https://example.com/api/ "

    assert_equal "https://example.com/api", config.normalized_public_base_url
  end

  def test_public_base_url_rejects_protocol_endpoint_query_and_non_http_urls
    config = A2A::Rails::Configuration.new

    config.public_base_url = "https://example.com/a2a"
    assert_raises(A2A::Rails::ConfigurationError) { config.normalized_public_base_url }

    config.public_base_url = "https://example.com?token=secret"
    assert_raises(A2A::Rails::ConfigurationError) { config.normalized_public_base_url }

    config.public_base_url = "ftp://example.com"
    assert_raises(A2A::Rails::ConfigurationError) { config.normalized_public_base_url }
  end

  def test_task_execution_mode_defaults_to_sync
    config = A2A::Rails::Configuration.new

    assert_equal :sync, config.task_execution_mode
  end

  def test_task_execution_mode_resolves_skill_then_agent_then_global
    handler = ->(message:, context:) { [message, context] }

    global_agent = Class.new(A2A::Rails::Agent) do
      name "Global"
      description "Uses global execution mode"
      version "1.0"
      skill :reply, description: "Reply", tags: ["reply"], handler: handler
    end

    agent_override = Class.new(A2A::Rails::Agent) do
      name "Agent Override"
      description "Overrides global execution mode"
      version "1.0"
      execution_mode :sync
      skill :reply, description: "Reply", tags: ["reply"], handler: handler
    end

    skill_override = Class.new(A2A::Rails::Agent) do
      name "Skill Override"
      description "Overrides agent execution mode"
      version "1.0"
      execution_mode :sync
      skill :reply,
        description: "Reply",
        tags: ["reply"],
        handler: handler,
        execution_mode: :async
    end

    config = A2A::Rails::Configuration.new
    config.task_execution_mode = :async

    assert_equal :async, config.resolve_task_execution_mode(
      agent: global_agent,
      skill: global_agent.skills.first
    )
    assert_equal :sync, config.resolve_task_execution_mode(
      agent: agent_override,
      skill: agent_override.skills.first
    )
    assert_equal :async, config.resolve_task_execution_mode(
      agent: skill_override,
      skill: skill_override.skills.first
    )
  end

  def test_invalid_global_task_execution_mode_is_rejected
    config = A2A::Rails::Configuration.new
    config.agent = "ConfigurationTest::Fixtures::RegisteredAgent"
    config.task_execution_mode = :later

    error = assert_raises(A2A::Rails::ConfigurationError) { config.validate! }
    assert_match(/task_execution_mode/, error.message)
  end

  def test_active_record_maintenance_defaults_are_explicit
    config = A2A::Rails::Configuration.new

    assert_equal 30 * 24 * 60 * 60, config.task_retention
    assert_equal 1_000, config.task_prune_batch_size
    assert_equal 10_000, config.max_tasks_per_owner
    assert_equal 100, config.max_task_history_entries
    assert_equal 50, config.max_task_artifacts
  end

  def test_memory_store_is_the_default_task_store
    config = A2A::Rails::Configuration.new

    assert_equal :memory, config.task_store
    assert_instance_of A2A::Rails::Task::MemoryStore, config.resolve_task_store
  end

  def test_custom_task_store_must_satisfy_store_contract
    config = A2A::Rails::Configuration.new
    custom = Object.new
    %i[save find transition cancel list].each do |method_name|
      custom.define_singleton_method(method_name) { |*, **| nil }
    end
    config.task_store = custom

    assert_same custom, config.resolve_task_store

    config.task_store = Object.new
    error = assert_raises(A2A::Rails::ConfigurationError) { config.resolve_task_store }
    assert_match(/missing methods/, error.message)
  end

  def test_active_record_store_is_lazy_and_uses_explicit_cursor_secret
    config = A2A::Rails::Configuration.new
    config.task_store = :active_record
    config.task_page_token_secret = "x" * 32

    store = config.resolve_task_store

    assert_instance_of A2A::Rails::Task::ActiveRecordStore, store
  end

  def test_active_record_store_rejects_short_explicit_cursor_secret
    config = A2A::Rails::Configuration.new
    config.task_store = :active_record
    config.task_page_token_secret = "short"

    error = assert_raises(A2A::Rails::ConfigurationError) { config.resolve_task_store }
    assert_match(/at least 32 bytes/, error.message)
  end

  def test_explicit_logger_overrides_rails_default_lookup
    config = A2A::Rails::Configuration.new
    logger = Object.new
    config.logger = logger

    assert_same logger, config.logger
  end

  def test_global_configure_yields_a_stable_configuration_object
    original = A2A::Rails.instance_variable_get(:@configuration)
    A2A::Rails.instance_variable_set(:@configuration, nil)

    yielded = A2A::Rails.configure do |config|
      config.agent = "ConfigurationTest::Fixtures::RegisteredAgent"
    end

    assert_same yielded, A2A::Rails.configuration
    assert_equal "ConfigurationTest::Fixtures::RegisteredAgent", yielded.agent
  ensure
    A2A::Rails.instance_variable_set(:@configuration, original)
  end
end
