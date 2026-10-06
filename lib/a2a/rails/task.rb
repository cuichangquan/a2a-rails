# frozen_string_literal: true

module A2A
  module Rails
    module Task
      STATES = %i[submitted working completed failed rejected canceled].freeze
      TERMINAL_STATES = %i[completed failed rejected canceled].freeze
    end
  end
end

require_relative "task/store"
require_relative "task/memory_store"
require_relative "task/artifact_mapper"
require_relative "task/result_mapper"
require_relative "task/lifecycle"
