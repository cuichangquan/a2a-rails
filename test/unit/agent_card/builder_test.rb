# frozen_string_literal: true

require_relative "../../test_helper"

class AgentCardBuilderTest < Minitest::Test
  Handler = ->(message:, context:) { [message, context] }

  def test_builds_v1_card_from_agent_and_does_not_expose_handler
    agent = build_agent do |klass|
      klass.skill :search_products,
        name: "Product Search",
        description: "Search products",
        tags: %w[shopping search],
        examples: ["Find a laptop"],
        input_modes: ["text/plain"],
        output_modes: ["application/json"],
        handler: Handler
    end

    card = A2A::Rails::AgentCard::Builder.new(
      agent: agent,
      public_base_url: "https://example.com/api/",
      request_base_url: "http://ignored.test"
    ).call

    assert_equal "Test Agent", card["name"]
    assert_equal "Test description", card["description"]
    assert_equal "1.0", card["version"]
    assert_equal "https://example.com/api/a2a", card.dig("supportedInterfaces", 0, "url")
    assert_equal "JSONRPC", card.dig("supportedInterfaces", 0, "protocolBinding")
    assert_equal "1.0", card.dig("supportedInterfaces", 0, "protocolVersion")
    assert_equal false, card.dig("capabilities", "streaming")
    assert_equal ["text/plain"], card["defaultInputModes"]
    assert_equal ["text/plain"], card["defaultOutputModes"]

    skill = card.fetch("skills").first
    assert_equal "search_products", skill["id"]
    assert_equal "Product Search", skill["name"]
    assert_equal ["shopping", "search"], skill["tags"]
    assert_equal ["Find a laptop"], skill["examples"]
    assert_equal ["text/plain"], skill["inputModes"]
    assert_equal ["application/json"], skill["outputModes"]
    refute skill.key?("handler")
    refute skill.key?(:handler)
  end

  def test_request_base_url_is_used_when_public_base_url_is_absent
    agent = build_agent do |klass|
      klass.skill :reply, description: "Reply", tags: %w[echo], handler: Handler
    end

    card = A2A::Rails::AgentCard::Builder.new(
      agent: agent,
      request_base_url: "http://localhost:3000"
    ).call

    assert_equal "http://localhost:3000/a2a", card.dig("supportedInterfaces", 0, "url")
  end

  def test_agent_is_validated_before_card_is_built
    agent = Class.new(A2A::Rails::Agent)
    agent.name "Incomplete"

    assert_raises(A2A::Rails::ConfigurationError) do
      A2A::Rails::AgentCard::Builder.new(agent: agent, request_base_url: "https://example.com").call
    end
  end

  def test_base_url_is_required
    agent = build_agent do |klass|
      klass.skill :reply, description: "Reply", tags: %w[echo], handler: Handler
    end

    error = assert_raises(A2A::Rails::ConfigurationError) do
      A2A::Rails::AgentCard::Builder.new(agent: agent).call
    end
    assert_match(/base_url/, error.message)
  end

  private

  def build_agent
    Class.new(A2A::Rails::Agent).tap do |klass|
      klass.name "Test Agent"
      klass.description "Test description"
      klass.version "1.0"
      yield klass
    end
  end
end
