# frozen_string_literal: true

module TaskContinuationStoreContract
  def continuation_task
    {
      id: "continuation-task", owner_id: "owner", context_id: "conversation",
      status: { state: :submitted, timestamp: Time.now.utc.iso8601(6) },
      history: [continuation_message("original")]
    }
  end

  def continuation_message(id, data = { "messageId" => false, "message_id" => nil, "nested" => [{}, []] })
    { message_id: id, role: :user, parts: [{ data: data, media_type: "application/json" }], metadata: {} }
  end

  def waiting_task(store)
    store.save(continuation_task)
    store.configure_execution("continuation-task", principal_id: "owner", execution: {
      agent_class_name: "ExampleAgent", skill_id: "report", execution_mode: :sync,
      turn_id: "turn-1", message_id: "original"
    })
    store.claim_execution("continuation-task", principal_id: "owner", turn_id: "turn-1")
    store.transition("continuation-task", principal_id: "owner", turn_id: "turn-1", state: :input_required,
      message: { message_id: "question-1", role: :agent, parts: [{ data: { "messageId" => false, "message_id" => nil } }] })
  end

  def test_continuation_preserves_identity_history_and_data
    store = build_continuation_store
    waiting_task(store)
    result = store.resume("continuation-task", message: continuation_message("reply"), turn_id: "turn-2", principal_id: "owner")
    assert result[:accepted]
    assert_equal "conversation", result[:task][:context_id]
    assert_equal :submitted, result[:task].dig(:status, :state)
    assert_equal "report", result[:task].dig(:execution, :skill_id).to_s
    assert_equal "turn-2", result[:task].dig(:execution, :turn_id)
    assert_equal %w[original question-1 reply], result[:task][:history].map { |entry| entry[:message_id] }
    assert_equal continuation_message("reply")[:parts][0][:data], result[:task].dig(:history, 2, :parts, 0, :data)
    assert_equal({ "messageId" => false, "message_id" => nil }, result[:task].dig(:history, 1, :parts, 0, :data))
  end

  def test_repeated_reply_returns_current_task_without_new_turn_even_after_completion
    store = build_continuation_store
    waiting_task(store)
    reply = continuation_message("reply")
    store.resume("continuation-task", message: reply, turn_id: "turn-2", principal_id: "owner")
    store.claim_execution("continuation-task", turn_id: "turn-2", principal_id: "owner")
    store.transition("continuation-task", state: :completed, turn_id: "turn-2", principal_id: "owner")
    result = store.resume("continuation-task", message: reply, turn_id: "not-used", principal_id: "owner")
    refute result[:accepted]
    assert_equal "turn-2", result[:task].dig(:execution, :turn_id)
    assert_equal :completed, result[:task].dig(:status, :state)
    assert_equal 3, result[:task][:history].size
    assert_raises(A2A::Rails::TaskMessageConflictError) do
      store.resume("continuation-task", message: continuation_message("reply", { "different" => true }), turn_id: "x", principal_id: "owner")
    end
    assert_raises(A2A::Rails::TaskNotResumableError) do
      store.resume("continuation-task", message: continuation_message("new"), turn_id: "x", principal_id: "owner")
    end
  end

  def test_fences_old_turn_and_legacy_writers
    store = build_continuation_store
    waiting_task(store)
    store.resume("continuation-task", message: continuation_message("reply"), turn_id: "turn-2", principal_id: "owner")
    assert_nil store.claim_execution("continuation-task", turn_id: "turn-1", principal_id: "owner")
    assert_nil store.claim_execution("continuation-task", principal_id: "owner")
    [nil, "turn-1"].each do |old_turn|
      task = store.transition("continuation-task", state: :failed, turn_id: old_turn, principal_id: "owner")
      assert_equal :submitted, task.dig(:status, :state)
    end
    store.claim_execution("continuation-task", turn_id: "turn-2", principal_id: "owner")
    assert_nil store.claim_execution("continuation-task", turn_id: "turn-2", principal_id: "owner")
    store.transition("continuation-task", state: :input_required, message: { message_id: "q2", role: :agent, parts: [{ text: "Again?" }] }, turn_id: "turn-2", principal_id: "owner")
    late = store.transition("continuation-task", state: :failed, turn_id: "turn-2", principal_id: "owner")
    assert_equal :input_required, late.dig(:status, :state)
    store.cancel("continuation-task", principal_id: "owner")
    late = store.transition("continuation-task", state: :completed, turn_id: "turn-2", principal_id: "owner")
    assert_equal :canceled, late.dig(:status, :state)
  end

  def test_atomic_owner_context_and_state_checks_leave_history_unchanged
    store = build_continuation_store
    original = waiting_task(store)
    assert_raises(A2A::Rails::TaskNotFoundError) do
      store.resume("continuation-task", message: continuation_message("reply"), turn_id: "turn-2", principal_id: "other")
    end
    assert_raises(A2A::Rails::TaskContextMismatchError) do
      store.resume("continuation-task", message: continuation_message("reply"), context_id: "wrong", turn_id: "turn-2", principal_id: "owner")
    end
    assert_raises(A2A::Rails::TaskContextMismatchError) do
      store.resume("continuation-task", message: continuation_message("reply"), context_id: "", turn_id: "turn-2", principal_id: "owner")
    end
    assert_equal original, store.find("continuation-task", principal_id: "owner")
  end

  def test_history_bound_rejects_without_truncating
    store = build_continuation_store(max_history_entries: 3)
    original = waiting_task(store)
    assert_raises(A2A::Rails::TaskStorePayloadLimitError) do
      store.resume("continuation-task", message: continuation_message("reply"), turn_id: "turn-2", principal_id: "owner")
    end
    assert_equal original, store.find("continuation-task", principal_id: "owner")
  end

  def test_legacy_task_remains_readable_but_cannot_resume
    store = build_continuation_store
    legacy = continuation_task
    legacy[:status][:state] = :input_required
    store.save(legacy)
    assert_equal "continuation-task", store.find("continuation-task", principal_id: "owner")[:id]
    assert_raises(A2A::Rails::TaskContinuationUnavailableError) do
      store.resume("continuation-task", message: continuation_message("reply"), turn_id: "turn-2", principal_id: "owner")
    end
  end
end
