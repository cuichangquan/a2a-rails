# frozen_string_literal: true

require "securerandom"

module A2A
  module Rails
    module Task
      class Lifecycle
        def initialize(store:, result_mapper: ResultMapper.new, logger: nil,
          clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.uuid })
          @store = store
          @result_mapper = result_mapper
          @logger = logger
          @clock = clock
          @id_generator = id_generator
        end

        def create(message:, context_id: nil)
          task = {
            id: next_id,
            context_id: present_context_id(context_id),
            status: status(:submitted),
            history: [copy(message)]
          }

          @store.save(task)
        end

        def start(task_id)
          @store.transition(task_id, state: :working, timestamp: now)
        end

        def complete(task_id, result)
          transition_from_outcome(task_id, @result_mapper.completed(result))
        end

        def reject(task_id, error)
          transition_from_outcome(task_id, @result_mapper.rejected(error))
        end

        def fail(task_id, error)
          log_failure(task_id, error)
          transition_from_outcome(task_id, @result_mapper.failed(error))
        end

        def cancel(task_id)
          @store.cancel(task_id, timestamp: now)
        end

        def find(task_id)
          @store.find(task_id)
        end

        def list(**filters)
          @store.list(**filters)
        end

        private

        def transition_from_outcome(task_id, outcome)
          attributes = { state: outcome.fetch(:state), timestamp: now }
          attributes[:artifacts] = outcome[:artifacts] if outcome.key?(:artifacts)
          attributes[:message] = outcome[:message] if outcome.key?(:message)
          @store.transition(task_id, **attributes)
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

          @logger.error("[a2a-rails] task_id=#{task_id} execution failed: #{error.class}: #{error.message}")
          @logger.error(error.backtrace.join("\n")) if error.backtrace && !error.backtrace.empty?
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
