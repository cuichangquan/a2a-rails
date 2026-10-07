# frozen_string_literal: true

begin
  require "rails/generators"
  require "rails/generators/migration"
  require "active_record"
  require "rails/generators/active_record"
rescue LoadError => error
  raise LoadError,
    "a2a:rails:task_store requires ActiveRecord in the host application (#{error.path})"
end

module A2A
  module Rails
    class TaskStoreGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      namespace "a2a:rails:task_store"
      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_task_store_migration
        migration_template(
          "create_a2a_rails_tasks.rb.tt",
          "db/migrate/create_a2a_rails_tasks.rb"
        )
      end

      def show_configuration
        say <<~MESSAGE

          Configure the durable store in config/initializers/a2a_rails.rb:

            config.task_store = :active_record

          Then run:

            bin/rails db:migrate
        MESSAGE
      end
    end
  end
end
