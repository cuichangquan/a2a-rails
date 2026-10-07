# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class ProductionSecurityHttpTest < Minitest::Test
  def test_production_mode_fails_closed_and_protects_real_rails_http_requests
    script = File.expand_path("../support/production_security_http_smoke.rb", __dir__)
    stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "production", "RACK_ENV" => "production" },
      RbConfig.ruby, script
    )

    assert status.success?, [stdout, stderr].reject(&:empty?).join("\n")
    assert_includes stdout, "Step 16-6 production HTTP security smoke: PASS"
  end
end
