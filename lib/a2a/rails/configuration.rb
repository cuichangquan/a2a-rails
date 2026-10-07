# frozen_string_literal: true

require "uri"

module A2A
  module Rails
    class Configuration
      attr_accessor :agent, :public_base_url, :authenticate_request, :authentication_challenge, :max_request_bytes

      def initialize
        @agent = nil
        @public_base_url = nil
        @authenticate_request = nil
        @authentication_challenge = 'Bearer realm="a2a"'
        @max_request_bytes = RequestGuard::DEFAULT_MAX_BYTES
        @logger_set = false
      end

      def logger
        return @logger if @logger_set
        return ::Rails.logger if defined?(::Rails) && ::Rails.respond_to?(:logger)

        nil
      end

      def logger=(value)
        @logger_set = true
        @logger = value
      end

      def validate!
        validate_agent_name!
        normalized_public_base_url
        self
      end

      def resolve_agent
        validate_agent_name!

        resolved = constantize(@agent.strip)
        unless resolved.is_a?(Class) && resolved <= A2A::Rails::Agent
          raise ConfigurationError, "Configured agent must inherit from A2A::Rails::Agent"
        end

        resolved.validate!
        resolved
      rescue NameError
        raise ConfigurationError, "Configured agent could not be resolved"
      end

      def normalized_public_base_url
        value = @public_base_url
        return nil if value.nil? || value.to_s.strip.empty?

        normalize_base_url(value.to_s)
      end

      private

      def validate_agent_name!
        unless @agent.is_a?(String) && !@agent.strip.empty?
          raise ConfigurationError, "config.agent must be a non-empty class-name String"
        end

        parts = @agent.strip.sub(/\A::/, "").split("::")
        unless parts.all? { |part| part.match?(/\A[A-Z]\w*\z/) }
          raise ConfigurationError, "config.agent must be a valid class-name String"
        end
      end

      def constantize(name)
        name.sub(/\A::/, "").split("::").reduce(Object) do |namespace, constant_name|
          namespace.const_get(constant_name, false)
        end
      end

      def normalize_base_url(value)
        uri = URI.parse(value.strip)
        unless %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty?
          raise ConfigurationError, "config.public_base_url must be an absolute HTTP(S) URL"
        end

        if uri.userinfo || uri.query || uri.fragment
          raise ConfigurationError, "config.public_base_url must not contain userinfo, query, or fragment"
        end

        segments = uri.path.to_s.split("/").reject(&:empty?)
        if segments.include?("a2a")
          raise ConfigurationError, "config.public_base_url must not contain /a2a"
        end

        uri.path = uri.path.to_s.sub(%r{/+\z}, "")
        uri.to_s.sub(%r{/+\z}, "")
      rescue URI::InvalidURIError
        raise ConfigurationError, "config.public_base_url must be an absolute HTTP(S) URL"
      end
    end
  end
end
