# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../test_helper"

class OptionalActiveRecordLoadingTest < Minitest::Test
  def test_base_gem_does_not_load_active_record
    script = <<~'RUBY'
      require "a2a-rails"

      loaded = $LOADED_FEATURES.grep(%r{/(active_record|activerecord)/})
      abort "ActiveRecord was loaded by base a2a-rails: #{loaded.join(", ")}" unless loaded.empty?

      puts "Base a2a-rails ActiveRecord load: PASS"
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-e",
      script
    )

    assert status.success?, [stdout, stderr].reject(&:empty?).join("\n")
    assert_includes stdout, "Base a2a-rails ActiveRecord load: PASS"
  end

  def test_activerecord_is_not_a_runtime_gemspec_dependency
    spec = Gem::Specification.load(File.expand_path("../../a2a-rails.gemspec", __dir__))

    refute_includes spec.runtime_dependencies.map(&:name), "activerecord"
    assert_includes spec.development_dependencies.map(&:name), "activerecord"
  end
end
