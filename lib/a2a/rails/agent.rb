# frozen_string_literal: true

module A2A
  module Rails
    class Agent
      UNSET = Object.new.freeze

      class << self
        def name(value = UNSET)
          return super() if value.equal?(UNSET)

          @a2a_name = value
        end

        def agent_name
          @a2a_name
        end

        def description(value = UNSET)
          return @a2a_description if value.equal?(UNSET)

          @a2a_description = value
        end

        def version(value = UNSET)
          return @a2a_version if value.equal?(UNSET)

          @a2a_version = value
        end

        def router(value = UNSET)
          return @a2a_router if value.equal?(UNSET)

          @a2a_router = value
        end

        def execution_mode(value = UNSET)
          return @a2a_execution_mode if value.equal?(UNSET)

          @a2a_execution_mode = value
        end

        # Task replies remain the default. A host may opt into direct Message
        # replies or provide a callable to choose the mode per request.
        def response_mode(value = UNSET)
          return @a2a_response_mode || :task if value.equal?(UNSET)

          @a2a_response_mode = value
        end

        def skill(id, description:, tags:, handler:, name: nil, examples: nil, input_modes: nil, output_modes: nil, execution_mode: nil)
          definition = Skill.new(
            id: id,
            name: name,
            description: description,
            tags: tags,
            handler: handler,
            examples: examples,
            input_modes: input_modes,
            output_modes: output_modes,
            execution_mode: execution_mode
          )
          skill_definitions << definition
          definition
        end

        def skills
          skill_definitions.dup.freeze
        end

        def validate!
          validate_metadata!
          validate_skills!
          validate_router!
          validate_response_mode!
          validate_execution_mode!
          self
        end

        private

        def skill_definitions
          @a2a_skills ||= []
        end

        def validate_metadata!
          {
            name: @a2a_name,
            description: @a2a_description,
            version: @a2a_version
          }.each do |field, value|
            next unless value.nil? || value.to_s.strip.empty?

            raise ConfigurationError, "#{self} must define #{field}"
          end
        end

        def validate_skills!
          if skill_definitions.empty?
            raise ConfigurationError, "#{self} must define at least one skill"
          end

          duplicate = skill_definitions.group_by(&:id).find { |_id, definitions| definitions.length > 1 }
          if duplicate
            raise ConfigurationError, "#{self} defines duplicate skill id: #{duplicate.first.inspect}"
          end

          skill_definitions.each(&:validate!)
        end

        def validate_response_mode!
          mode = response_mode
          return if %i[task message].include?(mode) || mode.respond_to?(:call)

          raise ConfigurationError, "response_mode must be :task, :message, or a callable"
        end

        def validate_execution_mode!
          mode = execution_mode
          return if mode.nil? || Configuration::TASK_EXECUTION_MODES.include?(mode)

          raise ConfigurationError, "execution_mode must be :sync or :async"
        end

        def validate_router!
          if skill_definitions.length > 1 && @a2a_router.nil?
            raise ConfigurationError, "#{self} defines multiple skills but no Router is configured"
          end

          return if @a2a_router.nil? || @a2a_router.respond_to?(:call)

          raise ConfigurationError, "Router #{@a2a_router.inspect} must respond to .call"
        end
      end
    end
  end
end
