# frozen_string_literal: true

require "securerandom"

module A2A
  module Rails
    module Task
      class Lifecycle
        attr_reader :principal_id

        def initialize(store:, result_mapper: ResultMapper.new, logger: nil,
          clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.uuid },
          principal_id: nil)
          @store = store
          @result_mapper = result_mapper
          @logger = logger
          @clock = clock
          @id_generator = id_generator
          @principal_id = principal_id
        end

        def create(message:, context_id: nil)
          task = {
            id: next_id,
            owner_id: @principal_id,
            context_id: present_context_id(context_id),
            status: status(:submitted),
            history: [copy(message)]
          }

          yield task if block_given?
          @store.save(task)
        end

        def start(task_id, turn_id: nil)
          @store.transition(task_id, state: :working, timestamp: now, principal_id: @principal_id, turn_id: turn_id)
        end

        def claim_execution(task_id, turn_id: nil)
          @store.claim_execution(task_id, timestamp: now, principal_id: @principal_id, turn_id: turn_id)
        end

        def complete(task_id, result, turn_id: nil)
          if result.is_a?(InputRequired)
            question = { message_id: next_id, role: :agent, parts: result.parts }
            transition_from_outcome(task_id, { state: :input_required, message: question }, turn_id: turn_id)
          else
            transition_from_outcome(task_id, @result_mapper.completed(result), turn_id: turn_id)
          end
        end

        def reject(task_id, error, turn_id: nil)
          transition_from_outcome(task_id, @result_mapper.rejected(error), turn_id: turn_id)
        end

        def fail(task_id, error, turn_id: nil)
          log_failure(task_id, error)
          transition_from_outcome(task_id, @result_mapper.failed(error), turn_id: turn_id)
        end

        def configure_execution(task_id, plan:, message_id:)
          @store.configure_execution(task_id, principal_id: @principal_id, execution: {
            agent_class_name: plan.agent_class_name,
            skill_id: plan.skill_id.to_s,
            execution_mode: plan.execution_mode.to_s,
            turn_id: next_id,
            message_id: message_id
          })
        end

        def resume(task_id, message:, context_id: nil)
          @store.resume(task_id, message: message, context_id: context_id,
            turn_id: next_id, timestamp: now, principal_id: @principal_id)
        end

        def cancel(task_id)
          @store.cancel(task_id, timestamp: now, principal_id: @principal_id)
        end

        def find(task_id)
          @store.find(task_id, principal_id: @principal_id)
        end

        def list(**filters)
          @store.list(**filters, principal_id: @principal_id)
        end

        private

        def transition_from_outcome(task_id, outcome, turn_id: nil)
          attributes = { state: outcome.fetch(:state), timestamp: now, turn_id: turn_id }
          attributes[:artifacts] = outcome[:artifacts] if outcome.key?(:artifacts)
          attributes[:message] = outcome[:message] if outcome.key?(:message)
          @store.transition(task_id, **attributes, principal_id: @principal_id)
        end

        def status(state)
          { state: state, timestamp: now.iso8601(6) }
        end

        def present_context_id(context_id)
          return context_id unless context_id.nil? || context_id.to_s.empty?

          next_id
        end

        def next_id
          @id_generator.call.to_s
        end

        def now
          @clock.call.utc
        end

        def log_failure(task_id, error)
          return unless @logger

          # Handler exception messages/backtraces can contain API keys,
          # credentials, or request data. Only emit the exception class.
          @logger.error("[a2a-rails] task_id=#{task_id} execution failed: #{error.class}")
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
