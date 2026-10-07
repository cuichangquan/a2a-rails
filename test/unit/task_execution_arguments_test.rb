# frozen_string_literal: true

require_relative "../test_helper"

class TaskExecutionArgumentsTest < Minitest::Test
  def test_serializes_only_minimal_queue_payload
    arguments = A2A::Rails::TaskExecutionArguments.new(
      task_id: "task-1",
      principal_id: "tenant-A:user-1",
      agent_class_name: "Agents::ReportAgent",
      skill_id: :build_report
    )

    assert_equal(
      {
        task_id: "task-1",
        principal_id: "tenant-A:user-1",
        agent_class_name: "Agents::ReportAgent",
        skill_id: "build_report"
      },
      arguments.to_h
    )
    assert_equal A2A::Rails::TaskExecutionArguments::KEYS, arguments.to_h.keys
    refute_includes arguments.to_h.keys, :message
    refute_includes arguments.to_h.keys, :context
    refute_includes arguments.to_h.keys, :authorization
    assert arguments.frozen?
    assert arguments.to_h.frozen?
    assert arguments.task_id.frozen?
    assert arguments.principal_id.frozen?
    assert arguments.agent_class_name.frozen?
    assert arguments.skill_id.frozen?
    assert_raises(FrozenError) { arguments.to_h[:message] = "secret" }
  end

  def test_allows_nil_principal_and_anonymous_agent_for_local_usage
    arguments = A2A::Rails::TaskExecutionArguments.new(
      task_id: "task-1",
      principal_id: nil,
      agent_class_name: nil,
      skill_id: "reply"
    )

    assert_nil arguments.principal_id
    assert_nil arguments.agent_class_name
  end

  def test_rejects_invalid_task_and_skill_identifiers
    ["", "bad\nvalue", "x" * 257, nil].each do |task_id|
      assert_raises(A2A::Rails::ConfigurationError) do
        A2A::Rails::TaskExecutionArguments.new(
          task_id: task_id,
          principal_id: nil,
          agent_class_name: nil,
          skill_id: "reply"
        )
      end
    end

    ["", "bad\tvalue", "x" * 257, Object.new].each do |skill_id|
      assert_raises(A2A::Rails::ConfigurationError) do
        A2A::Rails::TaskExecutionArguments.new(
          task_id: "task-1",
          principal_id: nil,
          agent_class_name: nil,
          skill_id: skill_id
        )
      end
    end
  end

  def test_reuses_verified_principal_id_constraints
    ["", "bad\nprincipal", "x" * 257, :symbol].each do |principal_id|
      assert_raises(A2A::Rails::ConfigurationError) do
        A2A::Rails::TaskExecutionArguments.new(
          task_id: "task-1",
          principal_id: principal_id,
          agent_class_name: "Agents::ReportAgent",
          skill_id: "reply"
        )
      end
    end
  end

  def test_rejects_invalid_agent_class_name
    ["", "agents::ReportAgent", "Agent-Name", "x" * 513].each do |agent_class_name|
      assert_raises(A2A::Rails::ConfigurationError) do
        A2A::Rails::TaskExecutionArguments.new(
          task_id: "task-1",
          principal_id: nil,
          agent_class_name: agent_class_name,
          skill_id: "reply"
        )
      end
    end
  end
end
