# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class ClientOnlyRailsBootTest < Minitest::Test
  def test_client_only_rails_host_has_no_server_routes_or_agent
    script = File.expand_path("../support/client_only_rails_smoke.rb", __dir__)
    stdout, stderr, result = Open3.capture3(RbConfig.ruby, script)

    assert result.success?, [stdout, stderr].reject(&:empty?).join("\n")
    assert_includes stdout, "Step 29-4b client-only Rails smoke: PASS"
  end
end
