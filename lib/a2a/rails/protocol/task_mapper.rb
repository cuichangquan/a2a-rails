# frozen_string_literal: true

module A2A
  module Rails
    module Protocol
      class TaskMapper
        STATE_TO_WIRE = {
          submitted: "TASK_STATE_SUBMITTED",
          working: "TASK_STATE_WORKING",
          completed: "TASK_STATE_COMPLETED",
          failed: "TASK_STATE_FAILED",
          rejected: "TASK_STATE_REJECTED",
          canceled: "TASK_STATE_CANCELED"
        }.freeze
        WIRE_TO_STATE = STATE_TO_WIRE.invert.freeze

        def dump(task, history_length: nil, include_artifacts: true)
          result = {
            "id" => task.fetch(:id),
            "contextId" => task.fetch(:context_id),
            "status" => dump_status(task)
          }

          if task.key?(:history)
            history = project_history(task[:history], history_length)
            result["history"] = history.map { |message| dump_message(message) }
          end

          if include_artifacts && task.key?(:artifacts)
            result["artifacts"] = task[:artifacts].map { |artifact| dump_artifact(artifact) }
          end

          result
        end

        def internal_state(value)
          return nil if value.nil?

          WIRE_TO_STATE.fetch(value) do
            raise InvalidTaskStateError, "Unknown task state: #{value.inspect}"
          end
        end

        def self.wire_state(value)
          STATE_TO_WIRE.fetch(value) { value.to_s }
        end

        private

        def dump_status(task)
          status = task.fetch(:status)
          result = {
            "state" => self.class.wire_state(status.fetch(:state)),
            "timestamp" => status[:timestamp]
          }

          if status[:message]
            result["message"] = {
              "messageId" => "status-#{task.fetch(:id)}-#{status.fetch(:state)}",
              "role" => "ROLE_AGENT",
              "parts" => [{ "text" => status[:message].to_s }]
            }
          end

          result.compact
        end

        def dump_message(message)
          result = {
            "messageId" => message.fetch(:message_id),
            "role" => message.fetch(:role) == :agent ? "ROLE_AGENT" : "ROLE_USER",
            "parts" => message.fetch(:parts).map { |part| dump_part(part) }
          }
          result["metadata"] = copy(message[:metadata]) if message.key?(:metadata)
          result
        end

        def dump_artifact(artifact)
          {
            "artifactId" => artifact.fetch(:artifact_id),
            "parts" => artifact.fetch(:parts).map { |part| dump_part(part) }
          }
        end

        def dump_part(part)
          result = {}
          result["text"] = part[:text] if part.key?(:text)
          result["data"] = copy(part[:data]) if part.key?(:data)
          result["raw"] = part[:raw] if part.key?(:raw)
          result["url"] = part[:url] if part.key?(:url)
          result["filename"] = part[:filename] if part.key?(:filename)
          if part.key?(:raw) || part.key?(:url)
            result["mediaType"] = part[:media_type] if part.key?(:media_type)
          end
          result["metadata"] = copy(part[:metadata]) if part.key?(:metadata)
          result
        end

        def project_history(history, history_length)
          return history if history_length.nil?
          return [] if history_length.zero?

          history.last(history_length)
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
