# frozen_string_literal: true

require "uri"

module A2A
  module Rails
    module AgentCard
      class Builder
        DEFAULT_INPUT_MODES = ["text/plain"].freeze
        DEFAULT_OUTPUT_MODES = ["text/plain"].freeze

        def initialize(agent:, public_base_url: nil, request_base_url: nil, security: {}, validator: Validator.new)
          @agent = agent
          @public_base_url = public_base_url
          @request_base_url = request_base_url
          @security = security
          @validator = validator
        end

        def call
          @agent.validate!

          card = {
            "name" => @agent.agent_name.to_s,
            "description" => @agent.description.to_s,
            "version" => @agent.version.to_s,
            "supportedInterfaces" => [
              {
                "url" => endpoint_url,
                "protocolBinding" => "JSONRPC",
                "protocolVersion" => "1.0"
              }
            ],
            "capabilities" => {
              "streaming" => false,
              "pushNotifications" => false,
              "extendedAgentCard" => false
            },
            "defaultInputModes" => DEFAULT_INPUT_MODES.dup,
            "defaultOutputModes" => DEFAULT_OUTPUT_MODES.dup,
            "skills" => @agent.skills.map { |skill| skill_hash(skill) }
          }

          card.merge!(@security) unless @security.empty?
          @validator.validate!(card)
        end

        private

        def endpoint_url
          base = @public_base_url
          base = @request_base_url if base.nil? || base.to_s.strip.empty?
          if base.nil? || base.to_s.strip.empty?
            raise ConfigurationError, "Agent Card requires public_base_url or request_base_url"
          end

          normalized = normalize_base_url(base.to_s)
          "#{normalized}/a2a"
        end

        def normalize_base_url(value)
          uri = URI.parse(value.strip)
          unless %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty?
            raise ConfigurationError, "Agent Card base URL must be an absolute HTTP(S) URL"
          end

          if uri.userinfo || uri.query || uri.fragment
            raise ConfigurationError, "Agent Card base URL must not contain userinfo, query, or fragment"
          end

          segments = uri.path.to_s.split("/").reject(&:empty?)
          if segments.include?("a2a")
            raise ConfigurationError, "Agent Card base URL must not contain /a2a"
          end

          uri.path = uri.path.to_s.sub(%r{/+\z}, "")
          uri.to_s.sub(%r{/+\z}, "")
        rescue URI::InvalidURIError
          raise ConfigurationError, "Agent Card base URL must be an absolute HTTP(S) URL"
        end

        def skill_hash(skill)
          data = {
            "id" => skill.id.to_s,
            "name" => skill.name,
            "description" => skill.description,
            "tags" => skill.tags.dup
          }
          data["examples"] = skill.examples.dup unless skill.examples.nil?
          data["inputModes"] = skill.input_modes.dup unless skill.input_modes.nil?
          data["outputModes"] = skill.output_modes.dup unless skill.output_modes.nil?
          data
        end
      end
    end
  end
end
