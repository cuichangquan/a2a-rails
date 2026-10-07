# frozen_string_literal: true

module A2A
  module Rails
    class TaskExecutionArguments
      MAX_IDENTIFIER_BYTES = 256
      MAX_CLASS_NAME_BYTES = 512
      KEYS = %i[task_id principal_id agent_class_name skill_id].freeze

      attr_reader(*KEYS)

      def initialize(task_id:, principal_id:, agent_class_name:, skill_id:)
        @task_id = normalize_identifier(task_id, "task_id")
        @principal_id = normalize_principal_id(principal_id)
        @agent_class_name = normalize_agent_class_name(agent_class_name)
        @skill_id = normalize_skill_id(skill_id)
        @payload = {
          task_id: @task_id,
          principal_id: @principal_id,
          agent_class_name: @agent_class_name,
          skill_id: @skill_id
        }.freeze
        freeze
      end

      def to_h
        @payload
      end

      private

      def normalize_identifier(value, label)
        unless safe_string?(value, max_bytes: MAX_IDENTIFIER_BYTES)
          raise ConfigurationError, "#{label} must be a non-empty safe String"
        end

        value.dup.freeze
      end

      def normalize_principal_id(value)
        return nil if value.nil?

        unless Authentication.valid_principal_id?(value)
          raise ConfigurationError, "principal_id must be a valid non-secret principal ID String"
        end

        value.dup.freeze
      end

      def normalize_agent_class_name(value)
        return nil if value.nil?

        unless safe_string?(value, max_bytes: MAX_CLASS_NAME_BYTES)
          raise ConfigurationError, "agent_class_name must be a safe class-name String"
        end

        parts = value.sub(/\A::/, "").split("::")
        unless parts.all? { |part| part.match?(/\A[A-Z]\w*\z/) }
          raise ConfigurationError, "agent_class_name must be a valid class-name String"
        end

        value.dup.freeze
      end

      def normalize_skill_id(value)
        string = value.is_a?(Symbol) ? value.to_s : value
        normalize_identifier(string, "skill_id")
      end

      def safe_string?(value, max_bytes:)
        value.is_a?(String) &&
          !value.strip.empty? &&
          value.bytesize <= max_bytes &&
          !value.match?(/[[:cntrl:]]/)
      end
    end
  end
end
