# frozen_string_literal: true

module TaskStoreContract
  def contract_task(id, owner_id: "tenant-A:user-1", state: :working,
    timestamp: "2026-10-07T00:00:00.000000Z", context_id: "contract-context")
    {
      id: id,
      owner_id: owner_id,
      context_id: context_id,
      status: { state: state, timestamp: timestamp },
      history: [
        {
          message_id: "message-#{id}",
          role: :user,
          parts: [{ text: id }]
        }
      ]
    }
  end

  def test_store_contract_owner_scoped_find_and_copy_isolation
    store = build_contract_store
    store.save(contract_task("private"))

    found = store.find("private", principal_id: "tenant-A:user-1")
    assert_equal "private", found[:id]

    found[:status][:state] = :failed
    assert_equal :working,
      store.find("private", principal_id: "tenant-A:user-1").dig(:status, :state)

    assert_raises(A2A::Rails::TaskNotFoundError) do
      store.find("private", principal_id: "tenant-B:user-1")
    end
  end

  def test_store_contract_execution_claim_only_starts_submitted_once
    store = build_contract_store
    store.save(contract_task("claim", state: :submitted))

    first = store.claim_execution(
      "claim",
      timestamp: Time.utc(2026, 10, 7, 1),
      principal_id: "tenant-A:user-1"
    )
    second = store.claim_execution(
      "claim",
      timestamp: Time.utc(2026, 10, 7, 2),
      principal_id: "tenant-A:user-1"
    )

    assert_equal :working, first.dig(:status, :state)
    assert_nil second
    assert_equal :working,
      store.find("claim", principal_id: "tenant-A:user-1").dig(:status, :state)
  end

  def test_store_contract_terminal_tasks_cannot_be_claimed_again
    store = build_contract_store
    %i[completed failed rejected canceled].each do |state|
      id = "terminal-claim-#{state}"
      original = store.save(contract_task(id, state: state))
      assert_nil store.claim_execution(id, principal_id: "tenant-A:user-1")
      assert_equal original, store.find(id, principal_id: "tenant-A:user-1")
    end
  end

  def test_store_contract_execution_claim_is_owner_scoped
    store = build_contract_store
    store.save(contract_task("private-claim", state: :submitted))

    assert_raises(A2A::Rails::TaskNotFoundError) do
      store.claim_execution(
        "private-claim",
        principal_id: "tenant-B:user-1"
      )
    end

    assert_equal :submitted,
      store.find("private-claim", principal_id: "tenant-A:user-1").dig(:status, :state)
  end

  def test_store_contract_cancel_submitted_prevents_execution_claim
    store = build_contract_store
    store.save(contract_task("queued-cancel", state: :submitted))

    canceled = store.cancel(
      "queued-cancel",
      timestamp: Time.utc(2026, 10, 7, 1),
      principal_id: "tenant-A:user-1"
    )
    claimed = store.claim_execution(
      "queued-cancel",
      timestamp: Time.utc(2026, 10, 7, 2),
      principal_id: "tenant-A:user-1"
    )

    assert_equal :canceled, canceled.dig(:status, :state)
    assert_nil claimed
    assert_equal :canceled,
      store.find("queued-cancel", principal_id: "tenant-A:user-1").dig(:status, :state)
  end

  def test_store_contract_cancel_working_wins_over_late_completion
    store = build_contract_store
    store.save(contract_task("working-cancel", state: :working))

    canceled = store.cancel(
      "working-cancel",
      timestamp: Time.utc(2026, 10, 7, 1),
      principal_id: "tenant-A:user-1"
    )
    late = store.transition(
      "working-cancel",
      state: :completed,
      timestamp: Time.utc(2026, 10, 7, 2),
      artifacts: [{ artifact_id: "late", parts: [{ text: "late" }] }],
      principal_id: "tenant-A:user-1"
    )

    assert_equal :canceled, canceled.dig(:status, :state)
    assert_equal canceled, late
    refute late.key?(:artifacts)
  end

  def test_store_contract_terminal_transition_is_idempotent
    store = build_contract_store
    store.save(contract_task("terminal"))

    completed = store.transition(
      "terminal",
      state: :completed,
      timestamp: Time.utc(2026, 10, 7, 1),
      artifacts: [{ artifact_id: "result", parts: [{ text: "done" }] }],
      principal_id: "tenant-A:user-1"
    )
    unchanged = store.transition(
      "terminal",
      state: :failed,
      timestamp: Time.utc(2026, 10, 7, 2),
      message: "too late",
      principal_id: "tenant-A:user-1"
    )

    assert_equal :completed, completed.dig(:status, :state)
    assert_equal completed, unchanged
  end

  def test_store_contract_cancel_and_terminal_rejection
    store = build_contract_store
    store.save(contract_task("cancel"))

    canceled = store.cancel(
      "cancel",
      timestamp: Time.utc(2026, 10, 7, 1),
      principal_id: "tenant-A:user-1"
    )
    assert_equal :canceled, canceled.dig(:status, :state)

    error = assert_raises(A2A::Rails::TaskNotCancelableError) do
      store.cancel("cancel", principal_id: "tenant-A:user-1")
    end
    assert_equal :canceled, error.state
  end

  def test_store_contract_pagination_excludes_later_inserts
    store = build_contract_store
    store.save(contract_task("old", timestamp: "2026-10-07T00:00:00.000000Z"))
    store.save(contract_task("new", timestamp: "2026-10-07T01:00:00.000000Z"))

    first = store.list(
      context_id: "contract-context",
      status: :working,
      page_size: 1,
      principal_id: "tenant-A:user-1"
    )
    assert_equal ["new"], first[:tasks].map { |task| task[:id] }
    assert_equal 2, first[:total_size]
    refute_empty first[:next_page_token]

    store.save(contract_task("newer", timestamp: "2026-10-07T02:00:00.000000Z"))

    second = store.list(
      context_id: "contract-context",
      status: :working,
      page_size: 1,
      page_token: first[:next_page_token],
      principal_id: "tenant-A:user-1"
    )

    assert_equal ["old"], second[:tasks].map { |task| task[:id] }
    assert_equal 2, second[:total_size]
    assert_equal "", second[:next_page_token]
  end

  def test_store_contract_cursor_is_bound_to_query_and_owner
    store = build_contract_store
    store.save(contract_task("one", timestamp: "2026-10-07T00:00:00.000000Z"))
    store.save(contract_task("two", timestamp: "2026-10-07T01:00:00.000000Z"))

    token = store.list(page_size: 1, principal_id: "tenant-A:user-1")
      .fetch(:next_page_token)

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      store.list(
        page_size: 1,
        page_token: token,
        context_id: "changed",
        principal_id: "tenant-A:user-1"
      )
    end

    assert_raises(A2A::Rails::InvalidTaskQueryError) do
      store.list(
        page_size: 1,
        page_token: token,
        principal_id: "tenant-B:user-1"
      )
    end
  end
end
