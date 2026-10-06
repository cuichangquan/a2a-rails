# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class GeneratedQuickStartTest < Minitest::Test
  def test_generated_echo_quick_start
    script = File.expand_path("../support/generated_quick_start_smoke.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script)

    assert status.success?, [stdout, stderr].reject(&:empty?).join("\n")
    assert_includes stdout, "Step 15-11 generated Quick Start smoke: PASS"
  end
end
