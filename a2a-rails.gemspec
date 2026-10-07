# frozen_string_literal: true

require_relative "lib/a2a/rails/version"

Gem::Specification.new do |spec|
  spec.name = "a2a-rails"
  spec.version = A2A::Rails::VERSION
  spec.authors = ["cuichangquan"]
  spec.summary = "Rails-native integration for exposing Rails applications as A2A agents"
  spec.description = "Expose Rails applications as A2A agents while keeping protocol SDK details behind an internal adapter boundary."
  spec.homepage = "https://github.com/cuichangquan/a2a-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "#{spec.homepage}#readme"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "agent2agent", "~> 2.0.0"
  spec.add_dependency "actionpack", ">= 8.0", "< 8.2"
  spec.add_dependency "activejob", ">= 8.0", "< 8.2"
  spec.add_dependency "json", "< 3"
  spec.add_dependency "rack", ">= 3.0", "< 4"
  spec.add_dependency "railties", ">= 8.0", "< 8.2"

  spec.add_development_dependency "activerecord", ">= 8.0", "< 8.2"
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "sqlite3", ">= 2.1", "< 3"
  # Puma only serves the localhost-only official A2A TCK SUT in CI/dev.
  spec.add_development_dependency "puma", ">= 6.6", "< 8"
end
