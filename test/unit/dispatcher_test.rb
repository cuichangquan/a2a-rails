# frozen_string_literal: true

require_relative "../test_helper"

class DispatcherTest < Minitest::Test
  def build_agent(handler:, router: nil, two_skills: false)
    Class.new(A2A::Rails::Agent) do
      name "Test Agent"
      description "Dispatcher test"
      version "1.0"
      router(router) if router

      skill :reply,
        description: "Reply",
        tags: ["reply"],
        handler: handler

      if two_skills
        skill :other,
          description: "Other",
          tags: ["other"],
          handler: handler
      end
    end
  end

  def test_single_skill_dispatches_automatically_and_adds_skill_id
    seen = nil
    handler = ->(message:, context:) do
      seen = [message, context]
      "ok"
    end
    agent = build_agent(handler: handler)
    dispatcher = A2A::Rails::Dispatcher.new(agent: agent)
    message = { role: :user, parts: [{ text: "Hello" }] }
    context = { task_id: "task-1", context_id: "context-1" }

    result = dispatcher.call(message: message, context: context)

    assert_equal "ok", result
    assert_same message, seen[0]
    assert_equal({ task_id: "task-1", context_id: "context-1", skill_id: :reply }, seen[1])
    assert_equal({ task_id: "task-1", context_id: "context-1" }, context)
  end

  def test_router_receives_read_only_skill_ids_and_selects_declared_skill
    router_seen = nil
    router = lambda do |message:, context:, skills:|
      router_seen = [message, context, skills]
      "other"
    end
    handler = ->(message:, context:) { context[:skill_id] }
    agent = build_agent(handler: handler, router: router, two_skills: true)
    dispatcher = A2A::Rails::Dispatcher.new(agent: agent)
    message = { role: :user }
    context = { task_id: "task-1", context_id: "context-1" }

    result = dispatcher.call(message: message, context: context)

    assert_equal :other, result
    assert_same message, router_seen[0]
    assert_same context, router_seen[1]
    assert_equal %i[reply other], router_seen[2]
    assert router_seen[2].frozen?
    assert_raises(FrozenError) { router_seen[2] << :another }
  end

  def test_plan_resolves_execution_mode_and_execute_does_not_route_again
    router_calls = 0
    router = lambda do |**|
      router_calls += 1
      :other
    end
    handler = ->(message:, context:) { [message, context[:skill_id]] }
    agent = build_agent(handler: handler, router: router, two_skills: true)
    agent.execution_mode :async
    dispatcher = A2A::Rails::Dispatcher.new(agent: agent)
    message = { role: :user }
    context = { task_id: "task-1", context_id: "context-1" }

    plan = dispatcher.plan(message: message, context: context)
    result = dispatcher.execute(plan: plan, message: message, context: context)

    assert plan.async?
    assert_equal :other, plan.skill_id
    assert_equal 1, router_calls
    assert_equal [message, :other], result
    assert_equal 1, router_calls
  end

  def test_unknown_router_selection_raises_unknown_skill_error
    router = ->(**) { :missing }
    handler = ->(message:, context:) { [message, context] }
    agent = build_agent(handler: handler, router: router, two_skills: true)

    error = assert_raises(A2A::Rails::UnknownSkillError) do
      A2A::Rails::Dispatcher.new(agent: agent).call(message: {}, context: {})
    end

    assert_match(/unknown skill/, error.message)
  end
end
