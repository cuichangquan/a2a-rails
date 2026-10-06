# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class RailsEngineHttpTest < Minitest::Test
  def test_real_host_rails_http_path
    script = File.expand_path("../support/rails_engine_http_smoke.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script)

    assert status.success?, [stdout, stderr].reject(&:empty?).join("\n")
    assert_includes stdout, "Step 15-10 Rails HTTP smoke: PASS"
  end
end
