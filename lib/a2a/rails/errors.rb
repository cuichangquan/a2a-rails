# frozen_string_literal: true

module A2A
  module Rails
    class Error < StandardError; end

    class ConfigurationError < Error; end
    class InvalidHandlerError < ConfigurationError; end
    class UnknownSkillError < ConfigurationError; end
  end
end
