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
