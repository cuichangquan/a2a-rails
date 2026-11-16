# frozen_string_literal: true

require "active_job"

module A2A
  module Rails
    class TaskExecutionJob < ::ActiveJob::Base
      queue_as :default
      # The Task is already persisted before enqueue. Keep the enqueue boundary
      # immediate and independent from any surrounding host Active Record transaction.
      self.enqueue_after_transaction_commit = false

      def perform(task_id:, principal_id:, agent_class_name:, skill_id:, turn_id: nil)
        arguments = TaskExecutionArguments.new(
          task_id: task_id,
          principal_id: principal_id,
          agent_class_name: agent_class_name,
          skill_id: skill_id,
          turn_id: turn_id
        )
        task_id = arguments.task_id
        principal_id = arguments.principal_id
        agent_class_name = arguments.agent_class_name
        skill_id = arguments.skill_id
        turn_id = arguments.turn_id

        configuration = A2A::Rails.configuration
        lifecycle = Task::Lifecycle.new(
          store: A2A::Rails.runtime.task_store,
          logger: configuration.logger,
          principal_id: principal_id
        )

        claimed = lifecycle.claim_execution(task_id, turn_id: turn_id)
        return unless claimed

        agent = configuration.resolve_agent
        unless agent_class_name.nil? || agent.name == agent_class_name
          raise ConfigurationError, "Queued Agent no longer matches configured Agent"
        end

        verify_execution!(claimed, agent_class_name: agent_class_name, skill_id: skill_id,
          turn_id: turn_id)
        message = execution_message(claimed)
        plan = ExecutionPlan.new(
          agent_class_name: agent_class_name,
          skill_id: skill_id,
          execution_mode: :async
        )
        context = {
          task_id: task_id,
          context_id: claimed.fetch(:context_id),
          principal_id: principal_id,
          idempotency_key: task_id,
          execution_turn_id: turn_id,
          history: copy(claimed.fetch(:history))
        }

        result = Dispatcher.new(agent: agent, configuration: configuration).execute(
          plan: plan,
          message: message,
          context: context
        )
        lifecycle.complete(task_id, result, turn_id: turn_id)
      rescue RejectedTask => error
        lifecycle.reject(task_id, error, turn_id: turn_id) if claimed
      rescue TaskNotFoundError
        nil
      rescue StandardError => error
        lifecycle.fail(task_id, error, turn_id: turn_id) if claimed
      end

      private

      def verify_execution!(task, agent_class_name:, skill_id:, turn_id:)
        execution = task[:execution]
        return if execution.nil? && turn_id.nil?

        unless execution.is_a?(Hash) && execution[:turn_id] == turn_id &&
            execution[:agent_class_name] == agent_class_name &&
            execution[:skill_id].to_s == skill_id && execution[:execution_mode].to_s == "async"
          raise ConfigurationError, "Queued execution does not match saved Task execution"
        end
      end

      def execution_message(task)
        history = task[:history]
        unless history.is_a?(Array)
          raise ConfigurationError, "Queued Task does not contain Message history"
        end

        execution = task[:execution]
        message = if execution
          history.find do |entry|
            entry.is_a?(Hash) && entry[:role].to_s == "user" &&
              entry[:message_id] == execution.fetch(:message_id)
          end
        else
          # Jobs serialized by 0.4.0 remain executable only for legacy Tasks.
          history.first
        end
        unless message.is_a?(Hash)
          raise ConfigurationError, "Queued Task does not contain its execution Message"
        end

        copy(message)
      end

      def copy(value)
        Marshal.load(Marshal.dump(value))
      end
    end
  end
end
