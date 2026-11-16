# frozen_string_literal: true

require_relative "../test_helper"

class DependencyCompatibilityTest < Minitest::Test
  def test_distributed_runtime_dependency_preserves_lower_range_and_blocks_incompatible_parser
    spec = Gem::Specification.load(File.expand_path("../../a2a-rails.gemspec", __dir__))
    dependency = spec.runtime_dependencies.find { |item| item.name == "regexp_parser" }
    refute_nil dependency
    %w[2.0.0 2.12.0 2.13.1].each do |version|
      assert dependency.requirement.satisfied_by?(Gem::Version.new(version)), version
    end
    %w[1.8.2 2.13.2 2.14.0 3.0.0].each do |version|
      refute dependency.requirement.satisfied_by?(Gem::Version.new(version)), version
    end
  end
end
