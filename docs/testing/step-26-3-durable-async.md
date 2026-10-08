# Step 26-3 — Durable ActiveJob crash and recovery contract

Date: **2026-10-08**  
Scope: **A3 release gate** in [Issue #62](https://github.com/cuichangquan/a2a-rails/issues/62).  
Implementation: [PR #68](https://github.com/cuichangquan/a2a-rails/pull/68) — [failure injection smoke](../../spikes/queue_adapters/failure_smoke.rb).  
CI: [ActiveJob queue adapter compatibility #37718397716](https://github.com/cuichangquan/a2a-rails/actions/runs/37718397716) — **4/4 PASS** (Rails 8.0/8.1 × Solid Queue 1.2/Sidekiq 7.3).

## What this test *does* exercise

The isolated Ruby 3.4 Rails fixture uses a persistent disk SQLite **ActiveRecordStore** with real **Solid Queue / Redis-backed Sidekiq** adapters and a **separate OS worker process**. A bounded gated Handler persists an invocation marker before blocking; the smoke **SIGKILLs the worker process group** and restarts a real worker. This is not the ActiveJob inline/test adapter or simply a mocked Task.

| Failure window or condition | Measured behavior / acceptance criterion |
| --- | --- |
| Task committed; adapter returns false or raises synchronously during enqueue | RequestHandler transitions the already persisted Task to **FAILED**, emits a generic status, and another Rails process sees the durable FAILED record |
| Process crash **after Task commit but before enqueue** | Task remains **SUBMITTED** with no executed Handler; queue has no automatic record of the missing enqueue. A host must reconcile; the smoke separately enqueues the *original Task ID* and checks single completion |
| Task canceled while still SUBMITTED | Re-deliveries cannot execute Handler; CANCELED stays terminal |
| Worker SIGKILL **after SUBMITTED → WORKING claim**, during Handler | Fresh Rails process sees durable **WORKING**, no terminal artifact; the persisted invocation marker proves the Handler had started |
| Duplicate delivery after a crashed WORKING Task / worker restart | The atomic Task claim refuses re-entry; Task remains WORKING and Handler invocation count does not increase. **There is no automatic successful recovery** |
| Host-side business deduplication | Fixture demonstrates a database **UNIQUE(principal_id, idempotency_key)** and idempotent inserts; this is **application code**, not a built-in Gem side-effect guarantee |
| Normal queue operational recovery | Stopped/restarted separate worker executes a newly submitted queued Task from the real queue; prior [Step 22 adapter evidence](queue-adapters.md) covers happy paths and actual HTTP |

The test-only enqueue adapter failure is deliberately injected into the **real persisted Task path**, not a claim that a complete Redis/PostgreSQL outage or every backend enqueue error mode has been reproduced. Real worker crash and queue delivery *are not mocks*.

## Guarantees and what is **not** guaranteed

1. When backed by a shared **atomic** Store such as `ActiveRecordStore`, only one claimant can move a given SUBMITTED Task into WORKING, even if Job delivery is duplicated.
2. Once a Task has been claimed, a retry/redelivery will not execute the Handler again while that Task remains WORKING or terminal. This suppresses duplicated *Handler starts* but intentionally leaves an **ambiguous WORKING** Task after an abrupt crash.
3. The Task is stored before enqueue. Synchronous enqueue failures are recorded as FAILED, but a crash between the Task DB commit and queue acknowledgement is a **distributed-transaction gap**. The Gem does not supply an outbox/reconciliation scheduler.
4. Cancellation before Handler start prevents work; cancellation after Handler start **cannot interrupt Ruby or undo external effects**. Terminal CANCELED may prevent a late result artifact but does not imply an HTTP request/payment/email was rolled back.
5. `context[:idempotency_key]` is the **Task ID**. A host must use its own database uniqueness/transaction or a remote provider's idempotency contract to prevent duplicate business side effects. A local database key cannot atomically guard external APIs.
6. A reconciler must **not blindly reset WORKING to SUBMITTED**: it may repeat an already committed external side effect. Reconcile business data and escalate uncertain work to an operator or a domain-specific resolution process.

## Required host runbook (not delivered as universal Gem automation)

- **Before deployment:** configure `task_store = :active_record`, migrate persistent PostgreSQL, choose an operated durable queue; provision a bounded worker, monitoring and retry policy. Plan a reconciliation method, domain-level idempotency keys and queue/DB backup-recovery arrangements.
- **SUBMITTED unusually long:** inspect worker/queue health and verify whether a Job was really enqueued. Only after investigation, consider re-enqueue using the **same Task ID** and verified principal/agent/skill; duplicate task claims will no-op.
- **WORKING unusually long:** assume the Handler **may already have committed external effects**. Investigate logs and business data first; do not simply requeue/reset. Use domain-specific reconciliation and controlled state handling.
- **FAILED/REJECTED/CANCELED:** never silently retry a completed business side effect. Any user-facing retry should produce a new Task and use a business-level deduplication key when appropriate.
- **Queue shutdown:** prefer graceful stop; verify unexpectedly killed workers and stalled Tasks, alert on age/backlog, audit recovery decisions. Test Sidekiq's and Solid Queue's backend-specific reclaim/retry behavior in the *actual deployed topology*.

## Explicit limits

- The integrated real-queue fixture uses **SQLite** for a portable persistent Store; the [PostgreSQL 16 locking test](../../spikes/active_record_store_postgres/smoke.rb) and [installed artifact + production Rails PostgreSQL matrix](published-gem-postgres.md) independently cover PostgreSQL semantics. This does **not** establish a single fully integrated production PostgreSQL + backend crash/failover test.
- SIGKILL is an injected process failure, not a simulated VM/network loss, DB failover, corrupt queue state or full disaster recovery.
- A **source-path candidate** is tested by the queue adapter workflow; Step 26-4 still requires a new exact **stable installed artifact** smoke and release approval. The already-published RubyGems `0.2.0.rc2` cannot be modified.
- The Gem has no generic exactly-once external API effect, forced in-flight cancellation, automatic WORKING reclamation or business policy verification.
- Passing A3 does not authorize public production. [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) stays **OPEN** until actual host controls and operational sign-off.

## Reproduction

```bash
cd spikes/queue_adapters
QUEUE_RAILS_VERSION='~> 8.1.0' bundle install
QUEUE_ADAPTER=solid_queue bundle exec ruby failure_smoke.rb
QUEUE_ADAPTER=sidekiq REDIS_URL=redis://127.0.0.1:6379/15 bundle exec ruby failure_smoke.rb
```

Use only isolated/disposable Redis and database instances. This smoke terminates its worker with SIGKILL by design.
