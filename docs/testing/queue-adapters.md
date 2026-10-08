# ActiveJob queue adapter compatibility — Step 22-8

The Gem uses the host application's ActiveJob adapter. Solid Queue and Sidekiq are dependencies only of `spikes/queue_adapters/Gemfile`; neither is a Gem runtime dependency.

## Reproduce

Requires Ruby 3.4, Bundler, and a **dedicated empty Redis database** for Sidekiq. Do not point this smoke at an application queue: it inspects the default queue and expects it to contain only its own Jobs.

```sh
cd spikes/queue_adapters
QUEUE_RAILS_VERSION='~> 8.1.0' bundle install
QUEUE_ADAPTER=solid_queue bundle exec ruby smoke.rb
QUEUE_ADAPTER=sidekiq REDIS_URL=redis://127.0.0.1:6379/15 bundle exec ruby smoke.rb
```

CI uses an ephemeral Redis 7 service per job and covers both adapters on Rails 8.0 and 8.1 with Ruby 3.4. Backend ranges are Solid Queue `~> 1.2.4` and Sidekiq `~> 7.3`; the smoke prints resolved versions. This is representative compatibility coverage, not certification of every backend/version/topology.

## What runs

A minimal Rails application uses a temporary SQLite database with ActiveRecordStore and a Handler invocation table. Invocation rows have no unique constraint, so a second Handler execution would be visible. Solid Queue stores its jobs in that same database; Sidekiq stores jobs in Redis. Workers load the same application in a **separate process**, using Solid Queue's supervisor or the Sidekiq CLI. No inline/fake queue mode or direct `perform_now` substitutes for delivery.

The smoke verifies:

- Task Job inherits the host-selected adapter.
- Real queue payload contains only `task_id`, `principal_id`, `agent_class_name`, `skill_id` application arguments.
- Before worker start, Handler invocation count is zero and the queued Task is SUBMITTED.
- Successful execution becomes COMPLETED; Handler failure becomes FAILED; rejection becomes REJECTED.
- Two deliveries of one Task produce one Handler invocation with the stable Task idempotency key and expected principal.
- A queued CANCELED Task produces no Handler invocation.
- Handled Handler failures do not enter the backend's failure/retry set.
- After stopping the worker, a new queued Task remains SUBMITTED and is completed once by a newly started worker.

Polling and worker shutdown are bounded. Process groups are terminated during cleanup, and the temporary database is removed. The smoke never flushes Redis.

## Limits

The Step 22-8 adapter smoke checks serialization/enqueue/delivery directly; the separate Step 22-9 HTTP smoke below checks the SendMessage path. Graceful worker restart does not prove recovery of a process killed during external side effects. Ambiguous WORKING Tasks still require explicit reconciliation. SQLite smoke does not replace the existing PostgreSQL row-lock contention CI. Solid Queue's separate queue-database topology and host transaction boundaries need additional deployment-specific validation.

A host must configure and operate both a shared/durable Task Store and a durable queue. Adapter compatibility does not close Issue #11 or authorize public-production deployment. No release version, tag or publication is changed.

References: [Solid Queue](https://github.com/rails/solid_queue), [Sidekiq ActiveJob integration](https://github.com/sidekiq/sidekiq/wiki/Active-Job).

## Step 22-9: Real Rails HTTP async E2E

The same four CI configurations also run:

```sh
QUEUE_ADAPTER=solid_queue bundle exec ruby http_smoke.rb
QUEUE_ADAPTER=sidekiq REDIS_URL=redis://127.0.0.1:6379/15 bundle exec ruby http_smoke.rb
```

This starts a Puma Rails server on **127.0.0.1:9997**, sends JSON-RPC requests over TCP using Net::HTTP, and runs a separate real queue worker. It uses static test-only Bearer credentials mapped to two owners; this does not demonstrate production credential verification. The shared Task database survives graceful Web and worker process restarts during the test.

- SendMessage returns SUBMITTED before any Handler runs with the worker stopped.
- A bounded test Handler gate allows both GetTask and ListTasks to observe WORKING; release leads to COMPLETED with an Artifact.
- HTTP failure/rejection paths become FAILED/REJECTED.
- Foreign-owner GetTask/CancelTask fail; foreign ListTasks is empty.
- The verified principal and stable Task idempotency key reach the worker Handler.
- A persisted invocation log verifies Router runs once per Task, solely on the HTTP side.
- Cancel before delivery prevents Handler start; Cancel during WORKING stays CANCELED without late artifacts.
- Restarting Web preserves queued/terminal Tasks and Artifacts; work submitted while the worker is stopped completes after worker restart.

This is loopback, test-environment E2E using SQLite. It is not a production deployment, hard-crash recovery test, or full A2A interoperability certification. PostgreSQL cross-process locking remains covered by the separate Store workflow. Reconciliation of ambiguous WORKING Tasks is still explicit.


## Step 26-3: Worker SIGKILL and unresolved execution windows

[Failure injection and recovery evidence](step-26-3-durable-async.md) extends the same Rails 8.0/8.1 × Solid Queue/Sidekiq matrix with **real worker SIGKILL while WORKING**, recovery by another process, duplicate Job delivery, canceled-before-start Jobs, and an illustrative host-side business idempotency unique constraint. [CI #37718397716](https://github.com/cuichangquan/a2a-rails/actions/runs/37718397716) passed 4/4.

Important: replaying an uncertain WORKING Task is deliberately blocked, **not** automatically recovered. Crash between Task DB commit and queue enqueue also remains a host reconciliation concern. The optional ActiveRecordStore is durable, but no generic exactly-once external business guarantee exists.
