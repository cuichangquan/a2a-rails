# frozen_string_literal: true

module A2A
  module Rails
    module AgentCard
      # A2A v1.0 Agent Card security metadata is declarative. The host Rails
      # application MUST independently verify the advertised credentials.
      #
      # Step 16-5 supports a verified HTTP Bearer profile only. Do not
      # advertise unimplemented API key, OAuth2, OIDC or mTLS profiles.
      class Security
        def initialize(configuration:, rails_environment: (defined?(::Rails) ? ::Rails.env : "development"))
          @configuration = configuration
          @rails_environment = rails_environment.to_s
        end

        def fields
          schemes = @configuration.security_schemes
          requirements = @configuration.security_requirements
          authenticator = @configuration.authenticate_request

          # Preserve the unauthenticated local Quick Start, but never
          # advertise an authentication method that has no verifier.
          if authenticator.nil? && schemes.nil? && requirements.nil?
            # A public Agent Card with no security requirements would falsely
            # imply that production's protected endpoint is open.
            return {} if %w[development test].include?(@rails_environment)

            raise ConfigurationError, "Agent Card cannot advertise unauthenticated production endpoint"
          end

          unless authenticator.respond_to?(:call)
            raise ConfigurationError, "Agent Card security needs a configured request authenticator"
          end

          unless schemes.is_a?(Hash) && !schemes.empty? &&
              requirements.is_a?(Array) && !requirements.empty?
            raise ConfigurationError, "authenticated Agent Cards require security_schemes and security_requirements"
          end

          normalized_schemes = schemes.each_with_object({}) do |(name, definition), output|
            unless nonempty_string?(name) && definition.is_a?(Hash) && definition.size == 1
              raise ConfigurationError, "invalid Agent Card security scheme"
            end

            scheme_type, details = definition.first
            case scheme_type
            when "httpAuthSecurityScheme"
              validate_http_auth!(details)
            else
              raise ConfigurationError, "unsupported Agent Card authentication scheme type"
            end
            output[name] = { scheme_type => details.dup }
          end

          validated_requirements = requirements.map do |requirement|
            unless requirement.is_a?(Hash) && requirement.keys == ["schemes"] &&
                requirement["schemes"].is_a?(Hash) && !requirement["schemes"].empty?
              raise ConfigurationError, "invalid Agent Card security requirement"
            end

            entries = requirement["schemes"].each_with_object({}) do |(name, scope_list), output|
              unless normalized_schemes.key?(name) &&
                  scope_list.is_a?(Hash) && scope_list.keys == ["list"] &&
                  scope_list["list"].is_a?(Array) &&
                  scope_list["list"].all? { |scope| nonempty_string?(scope) }
                raise ConfigurationError, "Agent Card requirement references unknown or invalid scheme"
              end
              unless scope_list["list"].empty?
                raise ConfigurationError, "Bearer HTTP auth must not advertise OAuth scopes"
              end
              output[name] = { "list" => [] }
            end
            { "schemes" => entries }
          end

          {
            "securitySchemes" => normalized_schemes,
            "securityRequirements" => validated_requirements
          }
        end

        private

        def nonempty_string?(value)
          value.is_a?(String) && !value.strip.empty? && value.bytesize <= 256 &&
            !value.match?(/[[:cntrl:]]/)
        end

        def validate_http_auth!(details)
          unless details.is_a?(Hash) &&
              (details.keys - %w[scheme description bearerFormat]).empty? &&
              nonempty_string?(details["scheme"]) &&
              optional_text?(details, "description") &&
              optional_text?(details, "bearerFormat")
            raise ConfigurationError, "invalid HTTP authentication declaration"
          end
          # In v1.0 a Bearer challenge is the only HTTP Auth profile we
          # currently verify together with Rails' authenticate_request hook.
          unless details["scheme"].casecmp?("Bearer")
            raise ConfigurationError, "only Bearer HTTP authentication is supported"
          end
          Authentication.validate_challenge!(@configuration.authentication_challenge)
          unless @configuration.authentication_challenge.match?(/\ABearer(?:\s|\z)/i)
            raise ConfigurationError, "Bearer Agent Card must use a Bearer WWW-Authenticate challenge"
          end
        end

        def optional_text?(hash, field)
          !hash.key?(field) || nonempty_string?(hash[field])
        end
      end
    end
  end
end
