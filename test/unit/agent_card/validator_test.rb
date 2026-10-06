# frozen_string_literal: true

require_relative "../../test_helper"

class AgentCardValidatorTest < Minitest::Test
  def setup
    @validator = A2A::Rails::AgentCard::Validator.new
  end

  def test_accepts_minimal_v01_card
    card = valid_card

    assert_same card, @validator.validate!(card)
  end

  def test_rejects_enabled_unsupported_capability
    card = valid_card
    card["capabilities"]["streaming"] = true

    error = assert_raises(A2A::Rails::ConfigurationError) { @validator.validate!(card) }
    assert_match(/streaming/, error.message)
  end

  def test_rejects_invalid_protocol_interface
    card = valid_card
    card["supportedInterfaces"][0]["protocolVersion"] = "0.3"

    assert_raises(A2A::Rails::ConfigurationError) { @validator.validate!(card) }
  end

  def test_rejects_handler_leakage
    card = valid_card
    card["skills"][0]["handler"] = "InternalHandler"

    error = assert_raises(A2A::Rails::ConfigurationError) { @validator.validate!(card) }
    assert_match(/Handler/, error.message)
  end

  def test_rejects_duplicate_skill_ids
    card = valid_card
    card["skills"] << card["skills"].first.dup

    assert_raises(A2A::Rails::ConfigurationError) { @validator.validate!(card) }
  end

  private

  def valid_card
    {
      "name" => "Echo Agent",
      "description" => "Echo messages",
      "version" => "1.0",
      "supportedInterfaces" => [
        { "url" => "https://example.com/a2a", "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" }
      ],
      "capabilities" => { "streaming" => false, "pushNotifications" => false, "extendedAgentCard" => false },
      "defaultInputModes" => ["text/plain"],
      "defaultOutputModes" => ["text/plain"],
      "skills" => [
        { "id" => "reply", "name" => "Reply", "description" => "Echo a message", "tags" => ["echo"] }
      ]
    }
  end
end
