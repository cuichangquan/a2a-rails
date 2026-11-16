# frozen_string_literal: true
require_relative "../test_helper"

class InputRequiredTest < Minitest::Test
  def test_owned_result_preserves_opaque_json_and_defensive_copies
    data = {"false" => false, "nil" => nil, "nested" => [[], {}]}
    result = A2A::Rails::InputRequired.new("question", data: data)
    data["false"] = true
    assert_equal false, result.parts.last[:data]["false"]
    result.parts.last[:data]["nested"] << 1
    assert_equal [[], {}], result.parts.last[:data]["nested"]
  end

  def test_validates_explicit_question_and_json_without_sdk_objects
    [nil, "", "   ", {}].each { |text| assert_raises(ArgumentError) { A2A::Rails::InputRequired.new(text) } }
    [[], {symbol: 1}, {"x" => Float::NAN}, {"x" => Object.new}].each do |data|
      assert_raises(ArgumentError) { A2A::Rails::InputRequired.new("question", data: data) }
    end
  end
end
