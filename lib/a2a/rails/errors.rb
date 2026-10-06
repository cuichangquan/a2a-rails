# frozen_string_literal: true

module A2A
  module Rails
    class Error < StandardError; end

    class ConfigurationError < Error; end
    class InvalidHandlerError < ConfigurationError; end
    class UnknownSkillError < ConfigurationError; end

    class RejectedTask < Error; end
    class ArtifactMappingError < Error; end

    class ProtocolError < Error; end
    class InvalidRequestError < ProtocolError; end
    class ContentTypeNotSupportedError < ProtocolError; end
    class TaskContinuationNotSupportedError < ProtocolError; end

    class TaskError < Error; end
    class TaskNotFoundError < TaskError
      attr_reader :task_id

      def initialize(task_id)
        @task_id = task_id
        super("Task not found: #{task_id}")
      end
    end

    class TaskNotCancelableError < TaskError
      attr_reader :task_id, :state

      def initialize(task_id, state:)
        @task_id = task_id
        @state = state
        super("Task #{task_id} is not cancelable from #{state}")
      end
    end

    class InvalidTaskQueryError < TaskError; end
    class InvalidTaskStateError < TaskError; end
  end
end
