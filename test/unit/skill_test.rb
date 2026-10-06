# frozen_string_literal: true

require_relative "../test_helper"

class SkillTest < Minitest::Test
  Callable = Class.new do
    def self.call(message:, context:)
      [message, context]
    end
  end

  def test_normalizes_id_name_and_tags
    skill = A2A::Rails::Skill.new(
      id: "search_products",
      description: "Search products",
      tags: %i[shopping search],
      handler: Callable
    )

    assert_equal :search_products, skill.id
    assert_equal "Search Products", skill.name
    assert_equal ["shopping", "search"], skill.tags
    assert skill.tags.frozen?
    assert skill.frozen?
    assert_same skill, skill.validate!
  end

  def test_custom_name_is_preserved
    skill = A2A::Rails::Skill.new(
      id: :reply,
      name: "Echo Reply",
      description: "Echo a message",
      tags: ["echo"],
      handler: Callable
    )

    assert_equal "Echo Reply", skill.name
  end

  def test_optional_agent_card_fields_are_preserved
    skill = A2A::Rails::Skill.new(
      id: :reply,
      description: "Echo",
      tags: ["echo"],
      examples: ["Hello"],
      input_modes: ["text/plain"],
      output_modes: ["application/json"],
      handler: Callable
    )

    assert_equal ["Hello"], skill.examples
    assert_equal ["text/plain"], skill.input_modes
    assert_equal ["application/json"], skill.output_modes
    assert skill.examples.frozen?
    assert_same skill, skill.validate!
  end

  def test_optional_mode_fields_must_be_non_empty_string_arrays
    skill = A2A::Rails::Skill.new(
      id: :reply,
      description: "Echo",
      tags: ["echo"],
      input_modes: [],
      handler: Callable
    )

    assert_raises(A2A::Rails::ConfigurationError) { skill.validate! }
  end

  def test_description_is_required
    skill = A2A::Rails::Skill.new(id: :reply, description: " ", tags: ["echo"], handler: Callable)

    error = assert_raises(A2A::Rails::ConfigurationError) { skill.validate! }
    assert_match(/description/, error.message)
  end

  def test_at_least_one_tag_is_required
    skill = A2A::Rails::Skill.new(id: :reply, description: "Echo", tags: [], handler: Callable)

    error = assert_raises(A2A::Rails::ConfigurationError) { skill.validate! }
    assert_match(/tag/, error.message)
  end

  def test_handler_must_be_callable
    skill = A2A::Rails::Skill.new(id: :reply, description: "Echo", tags: ["echo"], handler: Object.new)

    error = assert_raises(A2A::Rails::InvalidHandlerError) { skill.validate! }
    assert_match(/respond to \.call/, error.message)
  end
end
