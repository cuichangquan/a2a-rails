# frozen_string_literal: true

require_relative "../test_helper"

class AgentCardSecurityTest < Minitest::Test
  def setup
    @configuration = A2A::Rails::Configuration.new
  end

  def security(environment: "production")
    A2A::Rails::AgentCard::Security.new(
      configuration: @configuration, rails_environment: environment
    ).fields
  end

  def configure_bearer
    @configuration.authenticate_request = ->(_request) { "verified-client" }
    @configuration.security_schemes = {
      "bearer" => {
        "httpAuthSecurityScheme" => { "scheme" => "Bearer", "bearerFormat" => "JWT" }
      }
    }
    @configuration.security_requirements = [
      { "schemes" => { "bearer" => { "list" => [] } } }
    ]
  end

  def test_anonymous_local_demo_card_has_no_security_declarations
    assert_equal({}, security(environment: "development"))
    assert_equal({}, security(environment: "test"))
  end

  def test_missing_verifier_in_production_does_not_advertise_public_agent
    assert_raises(A2A::Rails::ConfigurationError) { security }
    assert_raises(A2A::Rails::ConfigurationError) { security(environment: "staging") }
  end

  def test_bearer_profile_advertises_schema_fields_exactly
    configure_bearer
    fields = security
    assert_equal "Bearer", fields.dig("securitySchemes", "bearer", "httpAuthSecurityScheme", "scheme")
    assert_equal "JWT", fields.dig("securitySchemes", "bearer", "httpAuthSecurityScheme", "bearerFormat")
    assert_equal [{ "schemes" => { "bearer" => { "list" => [] } } }], fields.fetch("securityRequirements")
    refute fields.key?("security")
    refute_includes fields.inspect, "verified-client"
  end

  def test_verifier_cannot_be_set_without_advertised_requirements
    @configuration.authenticate_request = ->(_request) { "verified-client" }
    assert_raises(A2A::Rails::ConfigurationError) { security }
  end

  def test_advertising_security_without_verifier_is_rejected
    configure_bearer
    @configuration.authenticate_request = nil
    assert_raises(A2A::Rails::ConfigurationError) { security }
  end

  def test_rejects_unknown_scheme_and_invalid_references
    configure_bearer
    @configuration.security_requirements = [{ "schemes" => { "wrong-name" => { "list" => [] } } }]
    assert_raises(A2A::Rails::ConfigurationError) { security }

    configure_bearer
    @configuration.security_schemes["bearer"] = { "unknownAuthenticationScheme" => {} }
    assert_raises(A2A::Rails::ConfigurationError) { security }

    configure_bearer
    @configuration.security_schemes["bearer"] = {
      "httpAuthSecurityScheme" => { "scheme" => "Bearer" },
      "apiKeySecurityScheme" => { "location" => "header", "name" => "X-Key" }
    }
    assert_raises(A2A::Rails::ConfigurationError) { security }
  end

  def test_rejects_non_bearer_http_auth_or_bad_challenge
    configure_bearer
    @configuration.security_schemes["bearer"]["httpAuthSecurityScheme"]["scheme"] = "Basic"
    assert_raises(A2A::Rails::ConfigurationError) { security }

    configure_bearer
    @configuration.authentication_challenge = 'Basic realm="wrong"'
    assert_raises(A2A::Rails::ConfigurationError) { security }
  end

  def test_rejects_invalid_requirements_and_unscoped_http_bearer
    configure_bearer
    @configuration.security_requirements = [{}]
    assert_raises(A2A::Rails::ConfigurationError) { security }

    configure_bearer
    @configuration.security_requirements = [
      { "schemes" => { "bearer" => { "list" => ["admin"] } } }
    ]
    assert_raises(A2A::Rails::ConfigurationError) { security }

    configure_bearer
    @configuration.security_requirements = [{ "schemes" => {} }]
    assert_raises(A2A::Rails::ConfigurationError) { security }
  end

  def test_card_cannot_be_mutated_via_original_config_hash
    configure_bearer
    fields = security
    @configuration.security_schemes["bearer"]["httpAuthSecurityScheme"]["scheme"] = "Basic"
    assert_equal "Bearer", fields.dig("securitySchemes", "bearer", "httpAuthSecurityScheme", "scheme")
  end
end
