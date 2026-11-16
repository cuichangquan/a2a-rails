# frozen_string_literal: true
require "open3"
require "rbconfig"
require_relative "../test_helper"
class ContinuationLogTest < Minitest::Test
  def test_actual_rails_logs_and_instrumentation_do_not_include_a2a_bodies
    script = File.expand_path("../support/continuation_log_smoke.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script)
    assert status.success?, [stdout, stderr].join("\n")
    assert_includes stdout, "Continuation request-local Rails log privacy: PASS"
  end
end
