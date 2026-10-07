# frozen_string_literal: true

module A2A
  module Rails
    class ExecutionPlan
      attr_reader :agent_class_name, :skill_id, :execution_mode

      def initialize(agent_class_name:, skill_id:, execution_mode:)
        @agent_class_name = normalize_agent_class_name(agent_class_name)
        @skill_id = normalize_skill_id(skill_id)
        @execution_mode = normalize_execution_mode(execution_mode)
        freeze
      end

      def async?
        @execution_mode == :async
      end

      private

      def normalize_agent_class_name(value)
        return nil if value.nil? || value.to_s.empty?

        value.to_s.dup.freeze
      end

      def normalize_skill_id(value)
        value.to_sym
      rescue NoMethodError
        raise ConfigurationError, "ExecutionPlan skill_id must be convertible to a Symbol"
      end

      def normalize_execution_mode(value)
        return value if Configuration::TASK_EXECUTION_MODES.include?(value)

        raise ConfigurationError, "ExecutionPlan execution_mode must be :sync or :async"
      end
    end
  end
end
