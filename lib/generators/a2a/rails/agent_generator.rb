# frozen_string_literal: true

require "rails/generators/named_base"

module A2A
  module Rails
    class AgentGenerator < ::Rails::Generators::NamedBase
      namespace "a2a:rails:agent"
      source_root File.expand_path("templates", __dir__)

      def create_agent
        template "agent.rb.tt", File.join("app/agents", class_path, "#{file_name}_agent.rb")
      end

      def agent_display_name
        file_name.split("_").map(&:capitalize).join(" ")
      end
    end
  end
end
