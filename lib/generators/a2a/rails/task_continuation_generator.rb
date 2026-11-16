# frozen_string_literal: true

require_relative "task_store_generator"

module A2A
  module Rails
    class TaskContinuationGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      namespace "a2a:rails:task_continuation"
      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_continuation_migration
        migration_template(
          "add_execution_to_a2a_rails_tasks.rb.tt",
          "db/migrate/add_execution_to_a2a_rails_tasks.rb"
        )
      end
    end
  end
end
