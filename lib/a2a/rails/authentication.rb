# frozen_string_literal: true

module A2A
  module Rails
    # Gate the A2A HTTP endpoint before the protocol adapter can parse or
    # dispatch a request. Task ownership is a separate security boundary
    # (Step 16-3); authenticating a caller alone does not isolate Tasks.
    module Authentication
      PRINCIPAL_ENV_KEY = "a2a.rails.principal_id"
      MAX_PRINCIPAL_BYTES = 256

      class Unauthorized < StandardError; end
      class Forbidden < StandardError; end
      class ConfigurationError < StandardError; end

      module_function

      def authenticate!(request:, configuration:, rails_environment:)
        # Never accept a pre-existing Rack environment value as a verified
        # principal: only the application's authenticator may populate it.
        request.env.delete(PRINCIPAL_ENV_KEY)
        validate_challenge!(configuration.authentication_challenge)

        authenticator = configuration.authenticate_request
        if authenticator.nil?
          # Preserve the published local Rails Quick Start in dev/test.
          # Every other Rails environment fails closed without an authenticator.
          return nil if %w[development test].include?(rails_environment.to_s)

          raise Unauthorized
        end

        unless authenticator.respond_to?(:call)
          raise ConfigurationError, "authenticate_request must respond to #call"
        end

        principal_id = authenticator.call(request)
        raise Unauthorized if principal_id.nil? || principal_id == false

        unless valid_principal_id?(principal_id)
          raise ConfigurationError, "authenticator must return a non-secret principal ID String"
        end

        # Retain only a stable, non-secret identity for future authorization
        # checks. Never copy Authorization credentials into the Rack env key.
        request.env[PRINCIPAL_ENV_KEY] = principal_id.dup.freeze
      end

      def validate_challenge!(value)
        if !value.is_a?(String) || value.empty? || value.bytesize > 512 ||
            value.match?(/[\r\n]/)
          raise ConfigurationError, "authentication_challenge must be a safe HTTP challenge String"
        end
      end

      def valid_principal_id?(value)
        value.is_a?(String) &&
          !value.strip.empty? &&
          value.bytesize <= MAX_PRINCIPAL_BYTES &&
          !value.match?(/[[:cntrl:]]/)
      end
    end
  end
end
