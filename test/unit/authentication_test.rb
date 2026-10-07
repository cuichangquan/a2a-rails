# frozen_string_literal: true

require_relative "../test_helper"

class AuthenticationTest < Minitest::Test
  Request = Struct.new(:env)

  def setup
    @config = A2A::Rails::Configuration.new
    @request = Request.new({})
  end

  def advertise_bearer!
    @config.security_schemes = {
      "bearer" => { "httpAuthSecurityScheme" => { "scheme" => "Bearer" } }
    }
    @config.security_requirements = [
      { "schemes" => { "bearer" => { "list" => [] } } }
    ]
  end

  def authenticate(environment = "production")
    A2A::Rails::Authentication.authenticate!(
      request: @request,
      configuration: @config,
      rails_environment: environment
    )
  end

  def test_missing_verifier_fails_closed_outside_development_and_test
    %w[production staging custom].each do |env|
      @request.env["a2a.rails.principal_id"] = "client-supplied"
      assert_raises(A2A::Rails::Authentication::Unauthorized) { authenticate(env) }
      refute @request.env.key?("a2a.rails.principal_id")
    end
  end

  def test_published_local_demo_remains_open_in_development_and_test
    %w[development test].each do |env|
      assert_nil authenticate(env)
      refute @request.env.key?("a2a.rails.principal_id")
    end
  end

  def test_configured_verifier_sets_only_verified_opaque_principal
    @request.env["a2a.rails.principal_id"] = "forged"
    seen = []
    advertise_bearer!
    @config.authenticate_request = lambda do |request|
      seen << request
      "verified-client-1"
    end

    result = authenticate
    assert_equal "verified-client-1", result
    assert_equal "verified-client-1", @request.env.fetch("a2a.rails.principal_id")
    assert_predicate result, :frozen?
    assert_equal [@request], seen
  end

  def test_verifier_always_applies_even_in_development
    advertise_bearer!
    @config.authenticate_request = ->(_request) { nil }
    assert_raises(A2A::Rails::Authentication::Unauthorized) { authenticate("development") }
  end

  def test_nil_and_false_from_verifier_are_unauthorized
    [nil, false].each do |value|
      advertise_bearer!
      @config.authenticate_request = ->(_request) { value }
      assert_raises(A2A::Rails::Authentication::Unauthorized) { authenticate }
    end
  end

  def test_forbidden_from_application_verifier_is_preserved
    advertise_bearer!
    @config.authenticate_request = ->(_request) { raise A2A::Rails::Authentication::Forbidden }
    assert_raises(A2A::Rails::Authentication::Forbidden) { authenticate }
  end

  def test_bad_verifier_or_principal_is_a_configuration_error
    advertise_bearer!
    @config.authenticate_request = "not-callable"
    assert_raises(A2A::Rails::Authentication::ConfigurationError) { authenticate }

    [true, 123, {}, "", " ", "a\nb", "x" * 257].each do |value|
      advertise_bearer!
      @config.authenticate_request = ->(_request) { value }
      assert_raises(A2A::Rails::Authentication::ConfigurationError) { authenticate }
    end
  end

  def test_verifier_without_agent_card_security_fails_closed
    @config.authenticate_request = ->(_request) { "verified-client" }

    assert_raises(A2A::Rails::ConfigurationError) { authenticate }
    refute @request.env.key?("a2a.rails.principal_id")
  end

  def test_challenge_rejects_response_splitting_and_invalid_values
    [nil, "", "Bearer\r\nX-Injection: yes", "x" * 513].each do |value|
      @config.authentication_challenge = value
      assert_raises(A2A::Rails::Authentication::ConfigurationError) { authenticate("development") }
    end
  end
end
