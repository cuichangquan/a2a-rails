# ActiveJob Task Execution Design

Status: accepted design; Step 22 implementation in progress / Issue #41.

## Goal

Move opt-in long-running A2A Task handlers out of the HTTP request cycle while preserving the existing synchronous behavior by default.

This Gem uses ActiveJob as the abstraction boundary. It does not own or require a specific queue backend.

## Non-goals

Step 22 does not promise:

- exactly-once external side effects;
- forceful termination of arbitrary running Ruby code;
- generic automatic Handler retries;
- queue-backend-specific cancellation;
- built-in business authorization;
- safe public production deployment by configuration alone.

## Execution modes

Default:

```ruby
config.task_execution_mode = :sync
```

Proposed precedence:

```text
Skill
  > Agent
    > global configuration
```

Example:

```ruby
A2A::Rails.configure do |config|
  config.task_execution_mode = :sync
end

class ReportsAgent < A2A::Rails::Agent
  execution_mode :sync

  skill :build_report,
    description: "Build a report",
    tags: ["report"],
    handler: BuildReport,
    execution_mode: :async
end
```

Only `:sync` and `:async` are supported initially. Step 22-2 implements this configuration surface and precedence; actual ActiveJob execution follows in later Step 22 work.

Async applies to Task responses. Direct Message responses remain synchronous because they do not create a persisted Task that can be polled later.

## Execution plan

Current Dispatching selects and executes a Skill in one operation. Async execution needs those concerns separated.

The HTTP process should resolve one immutable internal execution plan after the Task exists:

```text
agent class name
skill id
execution mode
```

The router is evaluated once. The worker must execute the selected Skill directly and must not route the same Message again.

This avoids nondeterministic routing and avoids serializing Handler objects or Procs into the queue.

## Synchronous flow

```text
SendMessage
  -> normalize Message
  -> persist SUBMITTED Task
  -> resolve ExecutionPlan
  -> atomic execution claim
  -> WORKING
  -> Handler
  -> COMPLETED | FAILED | REJECTED
  -> return terminal Task
```

This remains the default behavior.

## Async flow

```text
SendMessage
  -> normalize Message
  -> persist and commit SUBMITTED Task
  -> resolve ExecutionPlan
  -> enqueue TaskExecutionJob
  -> return SUBMITTED Task

TaskExecutionJob
  -> reconstruct trusted principal context
  -> owner-scoped Task lookup
  -> atomic SUBMITTED -> WORKING claim
  -> read original Message from Task history
  -> execute selected Skill directly
  -> COMPLETED | FAILED | REJECTED
```

The Task Store is the source of truth. ActiveJob is the delivery mechanism.

## Job arguments

Keep Job arguments minimal:

```text
task_id
principal_id
agent_class_name
skill_id
```

Never enqueue:

- Authorization credentials;
- Rack env / request objects;
- the full inbound Message;
- arbitrary Handler objects;
- secrets.

The Job reloads the original Message from the Task Store using the verified owner scope.

## Handler context

Sync and async execution should receive the same additive context:

```ruby
{
  task_id: task.id,
  context_id: task.context_id,
  skill_id: skill.id,
  principal_id: principal_id,
  idempotency_key: task.id
}
```

`principal_id` is the already-verified, stable, non-secret identity from the host authentication hook. It is not a replacement for host business authorization.

The stable Task ID is also exposed as an idempotency key for host business operations.

## Atomic execution claim

Async delivery can be duplicated. General Task transition is not sufficient to protect Handler start.

Add an async Store capability:

```ruby
claim_execution(task_id, principal_id:, timestamp:)
```

Required semantics:

- only `SUBMITTED -> WORKING` may win;
- the state check and transition are atomic;
- exactly one concurrent claimant wins;
- WORKING or terminal Tasks produce a non-winning/no-op result;
- lookup remains scoped by `owner_id + task_id`.

Implementation:

- MemoryStore: mutex-protected, local/test-oriented.
- ActiveRecordStore: transaction + row lock + submitted-state check.
- custom Store: required only if the host opts into async execution.

Existing custom Stores using only synchronous execution must not become invalid merely because this optional capability exists.

## Persistence and enqueue boundary

The safe portable ordering is:

```text
1. commit SUBMITTED Task
2. enqueue ActiveJob
3. return SUBMITTED Task
```

Do not rely on a queue sharing the same database transaction as the Task Store.

If enqueue returns false or raises synchronously, transition the Task to FAILED with sanitized status data.

A process can still crash between Task commit and queue acknowledgement. This design does not claim a distributed transaction. Atomic execution claim makes future reconciliation/re-enqueue possible without allowing two Jobs to start the same SUBMITTED Task.

## Retry policy

No generic automatic Handler retry in the initial implementation.

The Gem-owned Job should not define `retry_on StandardError`.

Reason:

```text
automatic retry
+ arbitrary business side effect
= possible duplicate side effect
```

Expected behavior:

- normal result -> COMPLETED;
- `RejectedTask` -> REJECTED;
- other Handler exception -> FAILED;
- Handler failures are handled into Task state and are not re-raised merely to request a queue retry.

Queue delivery itself can still be at-least-once. The atomic Task claim prevents duplicate Handler start while the Task remains SUBMITTED, but the Gem cannot guarantee exactly-once behavior for remote APIs, payments, email, or other external side effects.

Hosts must use `task_id` / `idempotency_key` with their own database or external API when exactly-once business semantics matter.

## Worker restart and crash

Three cases have different guarantees.

### Queued but not started

A durable ActiveJob backend can retain the Job across worker restarts.

### Duplicate delivery before Handler start

Atomic Task claim prevents more than one Job from starting a SUBMITTED Task.

### Crash after WORKING

This is ambiguous: the Gem cannot know whether the Handler already produced an external side effect.

The first Step 22 implementation must not automatically replay ambiguous WORKING Tasks. Prefer explicit operator reconciliation over hidden duplicate side effects.

Execution leases / stale-WORKING recovery can be designed later as a separate feature.

## Cancellation

A2A cancellation is best effort.

### SUBMITTED

```text
SUBMITTED -> CANCELED
```

If the queued Job runs later, it cannot claim the terminal Task and exits without starting the Handler.

### WORKING

ActiveJob does not provide one portable queue-neutral API for force-killing arbitrary currently running Handler code.

Therefore Step 22 must:

- avoid Sidekiq/Solid Queue/Resque private cancellation APIs;
- check Task state before Handler start;
- preserve terminal-state immutability;
- never let late Handler completion change CANCELED to COMPLETED/FAILED;
- document that cancellation does not roll back external side effects.

Cooperative cancellation tokens may be considered separately.

## ActiveJob ownership

Use a Gem-owned Job based directly on `ActiveJob::Base`, e.g.:

```ruby
A2A::Rails::TaskExecutionJob < ActiveJob::Base
```

Do not inherit host `ApplicationJob` because its global retry/discard callbacks are outside the Gem's control.

The host chooses and operates the ActiveJob adapter.

## Production requirements

Async production execution requires both:

1. shared/durable Task storage, preferably `ActiveRecordStore` or an equivalent custom Store;
2. a durable ActiveJob backend.

MemoryStore + an in-process queue is acceptable for local/dev/test demonstrations, not restart-safe production.

Step 22 does not close the deployment gates in Issue #11. Real token verification, business authorization, ingress/TLS, rate/concurrency limits, budgets, observability, durable queue operation, and release verification remain deployment responsibilities.

## Retention

Existing retention starts when the Task reaches a terminal state.

SUBMITTED and WORKING Tasks are not normal terminal-retention candidates.

Stale nonterminal recovery must not be silently mixed into the existing prune command.

## Verification plan

1. execution-mode precedence tests;
2. ExecutionPlan / route-once tests;
3. shared atomic-claim contract for MemoryStore and ActiveRecordStore;
4. principal and Job payload tests;
5. enqueue failure tests;
6. no-generic-retry tests;
7. cancel-before-start and cancel/complete race tests;
8. real Solid Queue smoke plus Sidekiq compatibility coverage through ActiveJob;
9. real Rails HTTP async E2E with ActiveRecordStore;
10. full existing Ruby/Rails CI, production security smoke, official TCK and Python/Go interoperability regression.

## Release rule

Step 22 changes runtime behavior after the historical `0.2.0.rc1` candidate.

A fresh versioned release candidate, exact Gem artifact verification, clean Rails installs, SHA256 recording, and explicit publication approval are required before any release.

Tracking: Issue #41.
