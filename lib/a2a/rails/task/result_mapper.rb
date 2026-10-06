# frozen_string_literal: true

module A2A
  module Rails
    module Task
      class ResultMapper
        FAILURE_MESSAGE = "Task execution failed"
        REJECTION_MESSAGE = "Task rejected"

        def initialize(artifact_mapper: ArtifactMapper.new)
          @artifact_mapper = artifact_mapper
        end

        def completed(value)
          artifact = @artifact_mapper.call(value)
          outcome = { state: :completed }
          outcome[:artifacts] = [artifact] if artifact
          outcome
        end

        def rejected(error)
          message = error.message.to_s.empty? ? REJECTION_MESSAGE : error.message.to_s
          { state: :rejected, message: message }
        end

        def failed(_error)
          { state: :failed, message: FAILURE_MESSAGE }
        end
      end
    end
  end
end
