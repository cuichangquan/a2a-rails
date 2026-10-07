# ActiveRecord Task Store

The ActiveRecord Task Store is the optional durable Task backend for a2a-rails.

It is intended for Rails applications that need Task state to survive process restarts and be visible across multiple Rails workers. The default remains the process-local `MemoryStore`.

## Enable it

Generate the migration:

```bash
bin/rails generate a2a:rails:task_store
bin/rails db:migrate
```

Then configure the Store:

```ruby
A2A::Rails.configure do |config|
  config.task_store = :active_record
end
```

Selecting `:active_record` lazily loads ActiveRecord. Applications that keep the default MemoryStore do not need ActiveRecord as an a2a-rails runtime dependency.

## Default maintenance policy

The ActiveRecord Store receives these defaults from `A2A::Rails::Configuration`:

```ruby
config.task_retention = 30.days
config.task_prune_batch_size = 1_000
config.max_tasks_per_owner = 10_000
config.max_task_history_entries = 100
config.max_task_artifacts = 50
```

These settings affect the ActiveRecord Store only. MemoryStore behavior remains unchanged.

### Retention

When a Task first reaches a terminal state — completed, failed, rejected, or canceled — the Store sets:

```text
expires_at = terminal status timestamp + task_retention
```

The default retention is 30 days.

`expires_at` means **eligible for maintenance deletion**. It does not make a Task disappear immediately. Until the row is pruned, normal Get/List operations can still return it.

Set `config.task_retention = nil` to disable automatic expiry timestamps. If you do that in production, you own the resulting table-growth policy.

### Bounded pruning

Delete expired Tasks with:

```bash
bin/rails a2a:rails:tasks:prune
```

Each SQL delete is bounded by `task_prune_batch_size` (default 1,000 rows).

The Rake task also stops after 100 batches by default, so one maintenance invocation does not try to remove an unlimited backlog.

Override the invocation cap when intentionally catching up:

```bash
A2A_TASK_PRUNE_MAX_BATCHES=20 bin/rails a2a:rails:tasks:prune
```

The Store never performs maintenance deletion in the request path.

### Aggregate maintenance stats

```bash
bin/rails a2a:rails:tasks:stats
```

The command prints aggregate counts only:

- total
- active
- terminal
- expired

It does not print Task IDs, owner IDs, message history, artifacts, or credentials.

## Per-owner admission guard

By default the ActiveRecord Store retains at most 10,000 non-expired Tasks per owner before rejecting creation with a generic capacity error.

Configure or disable it:

```ruby
config.max_tasks_per_owner = 25_000
# or:
config.max_tasks_per_owner = nil
```

This is an **application resource guard**, not an authorization control and not a billing-grade strict quota.

The initial implementation checks the retained count and creates the Task in one transaction, but a small concurrency race is still possible when multiple processes create Tasks for the same owner simultaneously. Use ingress/application concurrency and cost controls for hard operational limits. A future strict quota could use a dedicated owner-counter/lock table.

## Stored collection bounds

The Store rejects persistence rather than silently truncating when:

- Task history exceeds `max_task_history_entries` (default 100);
- Task artifacts exceed `max_task_artifacts` (default 50).

This avoids unbounded JSON growth changing database size unexpectedly.

These limits apply at the persistence boundary. The existing HTTP request-size limit still protects individual inbound requests.

## Database concurrency

Task transition and cancellation use a database transaction and row lock.

This prevents two Rails workers from independently overwriting terminal Task state based on stale reads.

The Store does **not** terminate already-running Handler code. ActiveJob/background execution and distributed cancellation remain separate concerns.

## Pagination

ActiveRecordStore uses signed opaque keyset cursors, not OFFSET.

The first page stores an internal database-row snapshot boundary in the signed token. Rows inserted later are excluded from that pagination walk.

The cursor is bound to:

- verified owner;
- filters;
- page size;
- last status timestamp;
- last Task ID.

A cursor from another owner or a changed query is rejected.

This is not a full point-in-time MVCC snapshot for rows whose status changes after page 1. See the [design document](../design/active-record-task-store.md) for the exact guarantee.

## Database maintenance owned by the host

a2a-rails owns logical Task lifecycle maintenance:

- expiry timestamps;
- bounded pruning;
- Task count guard;
- stored collection limits;
- aggregate Task counts.

The host/infrastructure still owns:

- PostgreSQL VACUUM / ANALYZE;
- backups and PITR;
- replication;
- disk monitoring;
- database connection pool sizing;
- database-specific index/partition tuning.

## Production status

A durable Task Store removes the process-local/restart-loss limitation of MemoryStore, but it does not by itself make an internet-facing deployment safe.

Production deployments still need the controls in [Production security](production-security.md): real credential verification, business authorization, TLS/proxy policy, distributed rate/concurrency limits, execution budgets, monitoring, and Handler side-effect review.
