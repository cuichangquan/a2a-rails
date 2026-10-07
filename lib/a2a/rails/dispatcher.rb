# frozen_string_literal: true

module A2A
  module Rails
    class Dispatcher
      def initialize(agent:)
        @agent = agent
      end

      def validate!
        @agent.validate!
        self
      end

      # Evaluated before creating a Task, so a direct Message leaves no
      # temporary or orphaned Task in the backing store.
      def response_mode(message:)
        validate!
        setting = @agent.response_mode
        mode = setting.respond_to?(:call) ? setting.call(message: message) : setting
        return mode if %i[task message].include?(mode)

        raise ConfigurationError, "response_mode must resolve to :task or :message"
      end

      def call(message:, context:)
        validate!
        skill = select_skill(message: message, context: context)
        handler_context = context.merge(skill_id: skill.id)

        skill.handler.call(message: message, context: handler_context)
      end

      private

      def select_skill(message:, context:)
        declared = @agent.skills
        return declared.first if declared.one?

        selected = @agent.router.call(
          message: message,
          context: context,
          skills: declared.map(&:id).freeze
        )
        selected_id = normalize_selected_id(selected)

        declared.find { |skill| skill.id == selected_id } ||
          raise(UnknownSkillError, "Router selected unknown skill: #{selected.inspect}")
      end

      def normalize_selected_id(value)
        value.to_sym
      rescue NoMethodError
        raise UnknownSkillError, "Router selected unknown skill: #{value.inspect}"
      end
    end
  end
end
