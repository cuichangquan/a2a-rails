# frozen_string_literal: true

require "uri"

module A2A
  module Rails
    module AgentCard
      class Validator
        def validate!(card)
          unless card.is_a?(Hash)
            raise ConfigurationError, "Agent Card must be a Hash"
          end

          validate_text!(card, "name")
          validate_text!(card, "description")
          validate_text!(card, "version")
          validate_interfaces!(card["supportedInterfaces"])
          validate_capabilities!(card["capabilities"])
          validate_string_array!(card["defaultInputModes"], "defaultInputModes", allow_empty: false)
          validate_string_array!(card["defaultOutputModes"], "defaultOutputModes", allow_empty: false)
          validate_skills!(card["skills"])
          card
        end

        private

        def validate_text!(hash, key)
          value = hash[key]
          return if value.is_a?(String) && !value.strip.empty?

          raise ConfigurationError, "Agent Card #{key} must be a non-empty String"
        end

        def validate_interfaces!(interfaces)
          unless interfaces.is_a?(Array) && !interfaces.empty?
            raise ConfigurationError, "Agent Card supportedInterfaces must contain at least one interface"
          end

          interfaces.each do |interface|
            unless interface.is_a?(Hash)
              raise ConfigurationError, "Agent Card interface must be a Hash"
            end

            validate_http_url!(interface["url"])
            unless interface["protocolBinding"] == "JSONRPC" && interface["protocolVersion"] == "1.0"
              raise ConfigurationError, "Agent Card v0.1 interface must use JSONRPC protocol version 1.0"
            end
          end
        end

        def validate_http_url!(value)
          uri = URI.parse(value.to_s)
          return if %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty? && uri.query.nil? && uri.fragment.nil?

          raise ConfigurationError, "Agent Card interface URL must be an absolute HTTP(S) URL"
        rescue URI::InvalidURIError
          raise ConfigurationError, "Agent Card interface URL must be an absolute HTTP(S) URL"
        end

        def validate_capabilities!(capabilities)
          unless capabilities.is_a?(Hash)
            raise ConfigurationError, "Agent Card capabilities must be a Hash"
          end

          %w[streaming pushNotifications extendedAgentCard].each do |key|
            unless capabilities[key] == false
              raise ConfigurationError, "Agent Card v0.1 capability #{key} must be false"
            end
          end
        end

        def validate_skills!(skills)
          unless skills.is_a?(Array) && !skills.empty?
            raise ConfigurationError, "Agent Card skills must contain at least one Skill"
          end

          ids = skills.map do |skill|
            unless skill.is_a?(Hash)
              raise ConfigurationError, "Agent Card Skill must be a Hash"
            end

            if skill.key?("handler") || skill.key?(:handler)
              raise ConfigurationError, "Agent Card must not expose Handler internals"
            end

            %w[id name description].each { |key| validate_text!(skill, key) }
            validate_string_array!(skill["tags"], "Skill tags", allow_empty: false)
            validate_string_array!(skill["examples"], "Skill examples", allow_empty: true) if skill.key?("examples")
            validate_string_array!(skill["inputModes"], "Skill inputModes", allow_empty: false) if skill.key?("inputModes")
            validate_string_array!(skill["outputModes"], "Skill outputModes", allow_empty: false) if skill.key?("outputModes")
            skill["id"]
          end

          duplicate = ids.group_by(&:itself).find { |_id, matches| matches.length > 1 }
          raise ConfigurationError, "Agent Card defines duplicate Skill id: #{duplicate.first}" if duplicate
        end

        def validate_string_array!(value, label, allow_empty:)
          valid = value.is_a?(Array) &&
            (allow_empty || !value.empty?) &&
            value.all? { |entry| entry.is_a?(String) && !entry.strip.empty? }
          return if valid

          raise ConfigurationError, "Agent Card #{label} must be an Array of non-empty Strings"
        end
      end
    end
  end
end
