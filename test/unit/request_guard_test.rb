# frozen_string_literal: true

require "stringio"
require_relative "../test_helper"

class RequestGuardTest < Minitest::Test
  GUARD = A2A::Rails::RequestGuard

  def env(body = "{}", type: "application/json", length: :auto, encoding: nil)
    rack_env = {
      "rack.input" => StringIO.new(body),
      "CONTENT_TYPE" => type
    }
    rack_env["CONTENT_LENGTH"] = (length == :auto ? body.bytesize.to_s : length) unless length.nil?
    rack_env["HTTP_CONTENT_ENCODING"] = encoding if encoding
    rack_env
  end

  def enforce(rack_env, max_bytes: 1_024)
    GUARD.enforce!(env: rack_env, max_bytes: max_bytes)
  end

  def test_allows_small_json_request_and_rewinds_using_bounded_copy
    input = env('{"jsonrpc":"2.0"}', type: "application/json; charset=UTF-8")
    original = input["rack.input"]

    assert enforce(input)
    assert_equal '{"jsonrpc":"2.0"}', input["rack.input"].read
    refute_same original, input["rack.input"]
    assert_equal 17, input["CONTENT_LENGTH"].to_i
  end

  def test_exact_limit_is_allowed_and_limit_plus_one_is_rejected
    assert enforce(env(JSON.generate("x" * 30)), max_bytes: 32)
    assert_raises(GUARD::PayloadTooLarge) { enforce(env(JSON.generate("x" * 31)), max_bytes: 32) }
  end

  def test_rejects_oversized_declared_length_before_reading
    input = env("{}", length: "10000")
    assert_raises(GUARD::PayloadTooLarge) { enforce(input, max_bytes: 100) }
    assert_equal 0, input["rack.input"].pos
  end

  def test_detects_oversized_body_without_content_length
    input = env("X" * 1025, length: nil)
    assert_raises(GUARD::PayloadTooLarge) { enforce(input, max_bytes: 1024) }
    assert_equal 1025, input["rack.input"].pos
  end

  def test_detects_falsely_understated_content_length
    assert_raises(GUARD::PayloadTooLarge) do
      enforce(env("a" * 200, length: "3"), max_bytes: 100)
    end
    assert_raises(GUARD::InvalidBody) do
      enforce(env("abcd", length: "3"), max_bytes: 100)
    end
  end

  def test_accepts_identity_encoding_and_rejects_compressed_or_form_bodies
    assert enforce(env("{}", encoding: "identity"))

    assert_raises(GUARD::UnsupportedMediaType) do
      enforce(env("{}", type: "application/x-www-form-urlencoded"))
    end
    assert_raises(GUARD::UnsupportedMediaType) do
      enforce(env("{}", type: nil))
    end
    assert_raises(GUARD::UnsupportedMediaType) do
      enforce(env("{}", encoding: "gzip"))
    end
  end

  def test_rejects_missing_input_and_malformed_content_length
    assert_raises(GUARD::InvalidBody) { enforce(env("{}", length: "not-a-length")) }
    assert_raises(GUARD::InvalidBody) { enforce(env("{}", length: "-5")) }

    input = env("{}")
    input.delete("rack.input")
    assert_raises(GUARD::InvalidBody) { enforce(input) }
  end

  def test_preflight_rejects_sdk_sensitive_malformed_part_shapes
    [nil, 1, "bad", []].each do |part|
      body = JSON.generate(
        "jsonrpc" => "2.0",
        "method" => "SendMessage",
        "id" => "bad-part",
        "params" => {
          "message" => { "messageId" => "m1", "role" => "ROLE_USER", "parts" => [part] }
        }
      )
      assert_raises(GUARD::InvalidBody) { enforce(env(body)) }
    end
  end

  def test_preflight_rejects_invalid_json
    assert_raises(GUARD::InvalidBody) { enforce(env("{malformed")) }
  end

  def test_invalid_limit_fails_closed_without_reading_input
    [nil, 0, -1, "1024", GUARD::MAX_CONFIGURABLE_BYTES + 1].each do |limit|
      input = env("{}")
      assert_raises(GUARD::InvalidConfiguration) { enforce(input, max_bytes: limit) }
      assert_equal 0, input["rack.input"].pos
    end
  end
end
