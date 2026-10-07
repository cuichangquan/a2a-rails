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

This checks real adapter serialization/enqueue/delivery with persistent Task state, not the HTTP SendMessage path; HTTP async E2E is Step 22-9. Graceful worker restart does not prove recovery of a process killed during external side effects. Ambiguous WORKING Tasks still require explicit reconciliation. SQLite smoke does not replace the existing PostgreSQL row-lock contention CI. Solid Queue's separate queue-database topology and host transaction boundaries need additional deployment-specific validation.

A host must configure and operate both a shared/durable Task Store and a durable queue. Adapter compatibility does not close Issue #11 or authorize public-production deployment. No release version, tag or publication is changed.

References: [Solid Queue](https://github.com/rails/solid_queue), [Sidekiq ActiveJob integration](https://github.com/sidekiq/sidekiq/wiki/Active-Job).
