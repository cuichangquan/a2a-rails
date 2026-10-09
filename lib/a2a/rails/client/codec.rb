# frozen_string_literal: true

module A2A
  module Rails
    class Client
      # Explicit A2A protocol keys only. Arbitrary JSON metadata/data and
      # unknown extension fields are opaque and must NOT have keys rewritten.
      module Codec
        KEYS = {
          "message_id" => "messageId",
          "context_id" => "contextId",
          "task_id" => "taskId",
          "artifact_id" => "artifactId",
          "media_type" => "mediaType",
          "mime_type" => "mimeType",
          "file_name" => "fileName",
          "supported_interfaces" => "supportedInterfaces",
          "protocol_binding" => "protocolBinding",
          "protocol_version" => "protocolVersion",
          "default_input_modes" => "defaultInputModes",
          "default_output_modes" => "defaultOutputModes",
          "input_modes" => "inputModes",
          "output_modes" => "outputModes",
          "accepted_output_modes" => "acceptedOutputModes",
          "return_immediately" => "returnImmediately",
          "history_length" => "historyLength",
          "page_size" => "pageSize",
          "page_token" => "pageToken",
          "next_page_token" => "nextPageToken",
          "total_size" => "totalSize",
          "status_timestamp_after" => "statusTimestampAfter",
          "include_artifacts" => "includeArtifacts",
          "security_schemes" => "securitySchemes",
          "security_requirements" => "securityRequirements",
          "extended_agent_card" => "extendedAgentCard",
          "push_notifications" => "pushNotifications"
        }.freeze
        REVERSE = KEYS.invert.freeze
        OPAQUE = %w[data metadata extensions securitySchemes securityRequirements].freeze

        module_function

        def encode(value, opaque: false)
          case value
          when Hash
            convert_hash(value, :encode, opaque: opaque)
          when Array
            value.map { |item| encode(item, opaque: opaque) }
          else
            value
          end
        end

        def decode(value, opaque: false)
          case value
          when Hash
            convert_hash(value, :decode, opaque: opaque)
          when Array
            value.map { |item| decode(item, opaque: opaque) }.freeze
          when String
            value.dup.freeze
          else
            value
          end
        end

        def convert_hash(value, direction, opaque:)
          result = {}
          value.each do |raw_key, entry|
            unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
              raise InvalidInputError, :invalid_hash_key
            end
            key = raw_key.to_s
            if direction == :encode
              output = opaque ? key : KEYS.fetch(key, key)
            else
              output = !opaque && REVERSE.key?(key) ? REVERSE.fetch(key).to_sym :
                (!opaque && KNOWN_KEYS.include?(key) ? key.to_sym : key)
            end
            raise InvalidInputError, :ambiguous_protocol_key if result.key?(output)
            child_opaque = opaque || OPAQUE.include?(key) || OPAQUE.include?(output.to_s)
            result[output] = if direction == :encode
              encode(entry, opaque: child_opaque)
            else
              decode(entry, opaque: child_opaque)
            end
          end
          direction == :decode ? result.freeze : result
        end

        KNOWN_KEYS = %w[
          id name description version skills capabilities streaming
          role parts text raw url data filename mimeType mediaType
          status state timestamp artifacts history message task tasks extensions
          tenant contextId messageId taskId artifactId
          supportedInterfaces protocolBinding protocolVersion
          defaultInputModes defaultOutputModes inputModes outputModes
          acceptedOutputModes returnImmediately historyLength
          pageSize pageToken nextPageToken totalSize
          statusTimestampAfter includeArtifacts metadata
          securitySchemes securityRequirements
        ].freeze
      end
    end
  end
end
