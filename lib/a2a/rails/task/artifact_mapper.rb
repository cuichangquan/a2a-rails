# frozen_string_literal: true

require "securerandom"

module A2A
  module Rails
    module Task
      class ArtifactMapper
        def initialize(id_generator: -> { SecureRandom.uuid })
          @id_generator = id_generator
        end

        def call(value)
          case value
          when nil
            nil
          when String
            artifact(parts: [{ text: value }])
          when Hash, Array
            artifact(parts: [{ data: copy(value) }])
          else
            raise ArtifactMappingError, "Unsupported Handler result type: #{value.class}"
          end
        end

        private

        def artifact(parts:)
          { artifact_id: @id_generator.call.to_s, parts: parts }
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
