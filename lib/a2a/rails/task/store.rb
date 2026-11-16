# frozen_string_literal: true

module A2A
  module Rails
    module Task
      class Store
        def save(_task)
          raise NotImplementedError, "Task stores must implement #save"
        end

        def find(_task_id, principal_id: nil)
          raise NotImplementedError, "Task stores must implement #find"
        end

        def transition(_task_id, state:, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task stores must implement #transition"
        end

        def claim_execution(_task_id, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task store does not implement async execution claim"
        end

        def cancel(_task_id, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task stores must implement #cancel"
        end

        def list(principal_id: nil, **_filters)
          raise NotImplementedError, "Task stores must implement #list"
        end

        def configure_execution(_task_id, execution:, principal_id: nil)
          raise TaskContinuationUnavailableError, "Task store must implement #configure_execution for execution turns"
        end

        def resume(_task_id, message:, context_id: nil, turn_id:, principal_id: nil, **_attributes)
          raise TaskContinuationUnavailableError, "Task store must implement atomic #resume"
        end

        def prune_expired(**_options)
          raise NotImplementedError, "Task store does not implement maintenance pruning"
        end

        def maintenance_stats(**_options)
          raise NotImplementedError, "Task store does not implement maintenance stats"
        end

        private

        def turn_matches?(task, turn_id)
          task.dig(:execution, :turn_id) == turn_id
        end

        def validate_turn_id!(turn_id)
          unless turn_id.is_a?(String) && !turn_id.empty?
            raise TaskContinuationUnavailableError, "Execution turn_id must be a nonempty String"
          end
        end

        def configured_execution(task, execution)
          unless task.dig(:status, :state) == :submitted && task[:execution].nil?
            raise TaskContinuationUnavailableError, "Execution can only be configured once on a submitted Task"
          end
          required = %i[skill_id execution_mode turn_id message_id]
          unless execution.is_a?(Hash) && required.all? { |key| !execution[key].to_s.empty? }
            raise TaskContinuationUnavailableError, "Execution metadata is incomplete"
          end
          validate_turn_id!(execution[:turn_id])
          execution.merge(skill_id: execution[:skill_id].to_s, execution_mode: execution[:execution_mode].to_s)
        end

        # Returns false for a previously accepted reply. The initial message is
        # deliberately not a continuation receipt; new-Task dedupe is out of scope.
        def validate_resume!(task, message, context_id, limit)
          if !context_id.nil? && context_id != task.fetch(:context_id)
            raise TaskContextMismatchError, "Message context does not match Task"
          end
          unless task[:execution].is_a?(Hash)
            raise TaskContinuationUnavailableError, "Legacy Task has no continuation metadata"
          end
          unless message.is_a?(Hash) && !message[:message_id].to_s.empty?
            raise InvalidRequestError, "Continuation message_id is required"
          end
          history = task[:history] || []
          prior_index = history.index { |entry| entry[:message_id] == message[:message_id] }
          if prior_index
            prior = history.fetch(prior_index)
            unless prior_index.positive? && prior[:role].to_s == "user" && canonical_message(prior) == canonical_message(message)
              raise TaskMessageConflictError, "Message ID has already been used with a different request"
            end
            return false
          end
          unless task.dig(:status, :state) == :input_required
            raise TaskNotResumableError.new(task.fetch(:id), state: task.dig(:status, :state))
          end
          # Reserve one slot for the handler's next question. Do not execute a
          # reply whose question cannot be persisted without discarding input.
          if history.length + 2 > limit
            raise TaskStorePayloadLimitError, "Task history limit reached; cancel and start a new Task"
          end
          true
        end

        def canonical_message(value)
          case value
          when Hash
            value.to_h { |key, item| [key.to_s, canonical_message(item)] }
          when Array
            value.map { |item| canonical_message(item) }
          when Symbol
            value.to_s
          else
            value
          end
        end
      end
    end
  end
end
