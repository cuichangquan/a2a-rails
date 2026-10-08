# frozen_string_literal: true

# Step 29-2 REFERENCE FIXTURE CHECKER ONLY.
# It validates proposed DTO examples, NOT any a2a-rails Client implementation.
# Run: ruby spikes/a2a_client_v03/public_contract_vectors_test.rb
require "json"

path = File.expand_path("../../test/contract/client_api/fixtures/vectors.json", __dir__)
examples = JSON.parse(File.read(path)).fetch("cases")
raise "Missing contract vectors" unless examples.size == 7

# This deliberately small, isolated normalizer is a **test oracle**, not code
# packaged into the Gem. Unknown field names and opaque metadata/data stay intact.
KNOWN = %w[
  task message id contextId status state timestamp artifacts artifactId parts
  text raw url data filename mediaType metadata history messageId role
  tasks nextPageToken pageSize totalSize
].freeze

def normalize_reference(value)
  case value
  when Array
    value.map { |v| normalize_reference(v) }
  when Hash
    out = {}
    value.each do |key, nested|
      recognized = KNOWN.include?(key)
      ruby_key = if recognized
        key.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').downcase.to_sym
      else
        key
      end
      raise "ambiguous normalized key: #{key.inspect}" if out.key?(ruby_key)
      out[ruby_key] = if %w[metadata data].include?(key) || !recognized
        nested  # opaque JSON, preserve exact string keys and values
      else
        normalize_reference(nested)
      end
    end
    out
  else
    value
  end
end

def normalize_case(example)
  wire = example.fetch("wire")
  case example.fetch("operation")
  when "SendMessage"
    names = %w[task message].select { |name| wire.key?(name) && !wire[name].nil? }
    raise "InvalidResponseError: SendMessage oneof" unless names.length == 1
    name = names.first
    { kind: name, name.to_sym => normalize_reference(wire.fetch(name)) }
  when "GetTask", "ListTasks"
    normalize_reference(wire)
  else
    raise "Unknown operation in fixture"
  end
end

assertions = 0
examples.each do |example|
  if example.key?("expected_error")
    begin
      normalize_case(example)
      raise "Expected #{example['expected_error']} for #{example['name']}"
    rescue RuntimeError => error
      raise unless error.message.start_with?("#{example.fetch('expected_error')}:")
    end
  else
    actual = JSON.parse(JSON.generate(normalize_case(example)))
    expected = example.fetch("expected")
    raise "Mismatch in #{example.fetch('name')}: #{actual.inspect}" unless actual == expected

    if example["name"] == "task-rich-parts"
      data = actual.dig("task", "artifacts", 0, "parts", 1, "data")
      raise "Nested arbitrary JSON keys were changed" unless data.dig("nested", "sameCase") == "preserved"
      raise "Opaque metadata key was changed" unless actual.dig("task", "metadata", "customKey") == "opaque"
    elsif example["name"] == "list-tasks-terminal-page"
      raise "Empty cursor must stay an empty string" unless actual["next_page_token"] == ""
    end
  end
  assertions += 1
  puts "PASS fixture: #{example.fetch('name')}"
end

puts "PASS: #{assertions} proposal fixture examples validated (no product Client tested)"
