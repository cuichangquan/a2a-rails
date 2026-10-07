# frozen_string_literal: true

require_relative "../test_helper"

class AgentTest < Minitest::Test
  Handler = Class.new do
    def self.call(message:, context:)
      [message, context]
    end
  end

  class NamedAgent < A2A::Rails::Agent
    name "Display Name"
    description "Named agent"
    version "1.0"
    skill :reply, description: "Reply", tags: ["reply"], handler: Handler
  end

  def build_agent(&block)
    Class.new(A2A::Rails::Agent, &block)
  end

  def test_declares_metadata_and_skills
    agent = build_agent do
      name "Echo Agent"
      description "Echo messages"
      version "1.0"

      skill :reply,
        description: "Echo a message",
        tags: %w[echo],
        handler: Handler
    end

    assert_equal "Echo Agent", agent.agent_name
    assert_equal "Echo messages", agent.description
    assert_equal "1.0", agent.version
    assert_equal [:reply], agent.skills.map(&:id)
    assert agent.skills.frozen?
    assert_same agent, agent.validate!
  end

  def test_response_mode_is_explicit_and_isolated_between_agents
    assert_equal :task, NamedAgent.response_mode
    direct = build_agent do
      name "Direct"
      description "Responds directly"
      version "1.0"
      response_mode :message
      skill :reply, description: "Reply", tags: ["reply"], handler: Handler
    end
    assert_equal :message, direct.response_mode
    assert_same direct, direct.validate!
    assert_equal :task, NamedAgent.response_mode
  end

  def test_invalid_response_mode_is_rejected
    invalid = build_agent do
      name "Invalid"
      description "Bad mode"
      version "1.0"
      response_mode :stream
      skill :reply, description: "Reply", tags: ["reply"], handler: Handler
    end
    error = assert_raises(A2A::Rails::ConfigurationError) { invalid.validate! }
    assert_match(/response_mode/, error.message)
  end

  def test_execution_mode_is_optional_and_isolated_between_agents
    assert_nil NamedAgent.execution_mode

    async_agent = build_agent do
      name "Async"
      description "Runs Tasks asynchronously"
      version "1.0"
      execution_mode :async
      skill :reply, description: "Reply", tags: ["reply"], handler: Handler
    end

    assert_equal :async, async_agent.execution_mode
    assert_same async_agent, async_agent.validate!
    assert_nil NamedAgent.execution_mode
  end

  def test_invalid_execution_mode_is_rejected
    invalid = build_agent do
      name "Invalid"
      description "Bad execution mode"
      version "1.0"
      execution_mode :later
      skill :reply, description: "Reply", tags: ["reply"], handler: Handler
    end

    error = assert_raises(A2A::Rails::ConfigurationError) { invalid.validate! }
    assert_match(/execution_mode/, error.message)
  end

  def test_skill_execution_mode_is_preserved_by_agent_dsl
    agent = build_agent do
      name "Mixed"
      description "Mixed execution modes"
      version "1.0"
      skill :reply,
        description: "Reply",
        tags: ["reply"],
        handler: Handler,
        execution_mode: :async
    end

    assert_equal :async, agent.skills.first.execution_mode
    assert_same agent, agent.validate!
  end

  def test_name_dsl_does_not_replace_ruby_class_name
    assert_equal "AgentTest::NamedAgent", NamedAgent.name
    assert_equal "Display Name", NamedAgent.agent_name
  end

  def test_skills_are_isolated_between_agent_subclasses
    first = build_agent do
      name "First"
      description "First agent"
      version "1.0"
      skill :one, description: "One", tags: ["one"], handler: Handler
    end
    second = build_agent do
      name "Second"
      description "Second agent"
      version "1.0"
      skill :two, description: "Two", tags: ["two"], handler: Handler
    end

    assert_equal [:one], first.skills.map(&:id)
    assert_equal [:two], second.skills.map(&:id)
  end

  def test_incomplete_agent_can_be_defined_but_fails_validation
    agent = build_agent do
      name "Echo Agent"
      description "Echo messages"
      version "1.0"
    end

    error = assert_raises(A2A::Rails::ConfigurationError) { agent.validate! }
    assert_match(/at least one skill/, error.message)
  end

  def test_duplicate_skill_ids_are_rejected
    agent = build_agent do
      name "Echo Agent"
      description "Echo messages"
      version "1.0"
      skill :reply, description: "One", tags: ["echo"], handler: Handler
      skill "reply", description: "Two", tags: ["echo"], handler: Handler
      router ->(**) { :reply }
    end

    error = assert_raises(A2A::Rails::ConfigurationError) { agent.validate! }
    assert_match(/duplicate skill id/, error.message)
  end

  def test_multiple_skills_require_router
    agent = build_agent do
      name "Shopping Agent"
      description "Shopping"
      version "1.0"
      skill :search, description: "Search", tags: ["search"], handler: Handler
      skill :purchase, description: "Purchase", tags: ["purchase"], handler: Handler
    end

    error = assert_raises(A2A::Rails::ConfigurationError) { agent.validate! }
    assert_match(/multiple skills/, error.message)
  end

  def test_router_must_be_callable
    agent = build_agent do
      name "Shopping Agent"
      description "Shopping"
      version "1.0"
      skill :search, description: "Search", tags: ["search"], handler: Handler
      skill :purchase, description: "Purchase", tags: ["purchase"], handler: Handler
      router Object.new
    end

    error = assert_raises(A2A::Rails::ConfigurationError) { agent.validate! }
    assert_match(/Router .* respond to \.call/, error.message)
  end
end
