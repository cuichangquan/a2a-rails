# frozen_string_literal: true

require_relative "../test_helper"

class LoadTest < Minitest::Test
  def test_version_is_defined
    assert_equal "0.1.0", A2A::Rails::VERSION
  end

  def test_protocol_adapter_classes_are_loaded
    assert defined?(A2A::Rails::Protocol::Adapter)
    assert defined?(A2A::Rails::Protocol::Agent2AgentAdapter)
  end
end
