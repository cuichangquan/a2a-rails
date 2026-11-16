# frozen_string_literal: true

# Runs in a genuinely separate dependency installation, never test_helper/source.
require "rubygems"
expected_version = ENV.fetch("A2A_RAILS_EXPECTED_VERSION")
expected_parser = ENV.fetch("REGEXP_PARSER_EXPECTED_VERSION")

begin
  require "a2a-rails"
rescue NoMethodError => error
  raise unless ENV["EXPECT_INCOMPATIBLE_PARSER"] == "1" && error.name == :implements &&
    error.backtrace.any? { |line| line.include?("json_schemer/ecma_regexp.rb") }
  abort "wrong published Gem" unless Gem.loaded_specs.fetch("a2a-rails").version.to_s == "0.5.0"
  abort "wrong schemer" unless Gem.loaded_specs.fetch("json_schemer").version.to_s == "2.5.0"
  abort "wrong parser" unless Gem.loaded_specs.fetch("regexp_parser").version.to_s == "2.13.2"
  puts "PASS reproduced known published 0.5.0 dependency incompatibility (implements)"
  exit
end
abort "expected incompatible parser to fail" if ENV["EXPECT_INCOMPATIBLE_PARSER"] == "1"
spec = Gem.loaded_specs.fetch("a2a-rails")
abort "wrong installed Gem" unless spec.version.to_s == expected_version
source = File.realpath(ENV.fetch("A2A_RAILS_SOURCE_ROOT"))
abort "loaded source checkout" if File.realpath(spec.full_gem_path).start_with?(source + File::SEPARATOR)
abort "wrong fresh parser resolution" unless Gem.loaded_specs.fetch("regexp_parser").version.to_s == expected_parser
require "json_schemer"
schema = JSONSchemer.schema({"type" => "string", "pattern" => "^a+$"})
abort "schema validation broken" unless schema.valid?("aaa") && !schema.valid?("bbb")
abort "public result missing" unless A2A::Rails::InputRequired.new("Which department?").is_a?(A2A::Rails::InputRequired)
puts "PASS installed #{spec.version}, parser #{expected_parser}, schema validation and public result"
