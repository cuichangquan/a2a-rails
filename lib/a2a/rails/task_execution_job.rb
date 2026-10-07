# frozen_string_literal: true

require "active_job"

module A2A
  module Rails
    class TaskExecutionJob < ::ActiveJob::Base
      queue_as :default

      def perform(task_id:, principal_id:, agent_class_name:, skill_id:)
        configuration = A2A::Rails.configuration
        lifecycle = Task::Lifecycle.new(
          store: A2A::Rails.runtime.task_store,
          logger: configuration.logger,
          principal_id: principal_id
        )

        claimed = lifecycle.claim_execution(task_id)
        return unless claimed

        agent = configuration.resolve_agent
        unless agent_class_name.nil? || agent.name == agent_class_name
          raise ConfigurationError, "Queued Agent no longer matches configured Agent"
        end

        message = original_message(claimed)
        plan = ExecutionPlan.new(
          agent_class_name: agent_class_name,
          skill_id: skill_id,
          execution_mode: :async
        )
        context = {
          task_id: task_id,
          context_id: claimed.fetch(:context_id),
          principal_id: principal_id,
          idempotency_key: task_id
        }

        result = Dispatcher.new(agent: agent, configuration: configuration).execute(
          plan: plan,
          message: message,
          context: context
        )
        lifecycle.complete(task_id, result)
      rescue RejectedTask => error
        lifecycle&.reject(task_id, error) if claimed
      rescue TaskNotFoundError
        nil
      rescue StandardError => error
        lifecycle&.fail(task_id, error) if claimed
      end

      private

      def original_message(task)
        history = task[:history]
        unless history.is_a?(Array) && history.first.is_a?(Hash)
          raise ConfigurationError, "Queued Task does not contain an original Message"
        end

        history.first
      end
    end
  end
end
