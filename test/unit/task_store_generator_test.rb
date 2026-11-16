# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require_relative "../test_helper"
require_relative "../../lib/generators/a2a/rails/task_store_generator"

class TaskStoreGeneratorTest < Minitest::Test
  def test_generator_creates_portable_task_store_migration
    Dir.mktmpdir("a2a-rails-task-store-generator") do |root|
      ::Rails::Generators.invoke(
        "a2a:rails:task_store",
        [],
        behavior: :invoke,
        destination_root: root
      )

      migrations = Dir[File.join(root, "db/migrate/*_create_a2a_rails_tasks.rb")]
      assert_equal 1, migrations.length

      body = File.read(migrations.first)
      expected_class = ::ActiveSupport::Inflector.camelize("create_a2a_rails_tasks")
      assert_includes body, "class #{expected_class} < ActiveRecord::Migration[8.0]"
      refute_includes body, "<%"

      assert_includes body, "create_table :a2a_rails_tasks"
      assert_includes body, "t.string :task_id, null: false"
      assert_includes body, "t.string :owner_id"
      assert_includes body, "t.json :history"
      assert_includes body, "t.json :artifacts"
      assert_includes body, "t.datetime :expires_at"
      assert_includes body, "idx_a2a_tasks_owner_task"
      assert_includes body, "idx_a2a_tasks_expires_at"
    end
  end
end

class TaskContinuationGeneratorTest < Minitest::Test
  def test_upgrade_generator_only_adds_execution_column
    require_relative "../../lib/generators/a2a/rails/task_continuation_generator"
    Dir.mktmpdir("a2a-rails-task-continuation-generator") do |root|
      ::Rails::Generators.invoke("a2a:rails:task_continuation", [], behavior: :invoke, destination_root: root)
      migrations = Dir[File.join(root, "db/migrate/*.rb")]
      assert_equal 1, migrations.size
      body = File.read(migrations.first)
      expected_class = ::ActiveSupport::Inflector.camelize("add_execution_to_a2a_rails_tasks")
      assert_includes body, "class #{expected_class} < ActiveRecord::Migration[8.0]"
      refute_includes body, "<%"
      assert_includes body, "add_column :a2a_rails_tasks, :execution, :json"
      refute_includes body, "create_table"
    end
  end
end

class TaskContinuationGeneratorTest
  def test_upgrade_generator_respects_host_acronym
    inflections = ActiveSupport::Inflector.inflections(:en)
    old_acronyms = inflections.acronyms.dup
    inflections.acronym("A2A")
    test_upgrade_generator_only_adds_execution_column
  ensure
    inflections.clear(:acronyms)
    old_acronyms.each_value { |word| inflections.acronym(word) }
  end
end
