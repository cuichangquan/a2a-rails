# Upgrade 0.4.0 → 0.5.0 candidate

Do not install an unpublished candidate version from RubyGems. Pin the reviewed
candidate artifact or exact source SHA and retain its hash/verification record.
After separate publication approval, pin the released Gem in both demos and rerun
unit/HTTP/TLS tests against the downloaded public bytes.

## Durable store migration / workers

1. Stop accepting new Tasks and continuation replies. Drain the old queue and stop
   all old workers. Record any ambiguous WORKING Tasks for application reconciliation.
2. Back up the database. With the candidate installed run
   `bin/rails generate a2a:rails:task_continuation`, then `bin/rails db:migrate`.
   The additive migration adds a nullable `execution` JSON column. Never rewrite an
   already-applied create-table migration. Fresh `a2a:rails:task_store` generation
   includes both migrations.
3. Start only new workers, then new web processes. Run get/list on old records and
   a new multi-turn canary before reopening traffic.

Old Tasks have no execution metadata. They remain readable/listable/cancelable, and
old four-key serialized Jobs can finish them using their original message. Do not
invent Agent/Skill/turn metadata or resume old records. New jobs include `turn_id`;
old workers reject this keyword and do not implement outcome fencing. **Mixed old
and new workers are unsupported.** There is no safe live rolling downgrade once
new-turn jobs exist. Roll back only after stopping traffic and draining/removing
new jobs with application review; retain the additive column and old records.
Cancel new Tasks explicitly before rollback if needed; cancellation does not undo
an already-performed external effect. Restore a backup only under an app-specific
recovery plan, never by blindly rolling back a migration with live tasks.

## Custom stores

Built-in MemoryStore and ActiveRecordStore implement atomic `configure_execution`
and `resume`; `claim_execution` and every `transition` accept and compare `turn_id`.
The full contract is in [Store](../../lib/a2a/rails/task/store.rb) and its shared
contract tests. Configuration rejects missing methods/abstract inherited methods
with a clear error. Custom Stores must implement the same atomic ownership,
context, state, deduplication, history bounds and stale-outcome semantics before
upgrading; merely accepting `**kwargs` is insufficient. This is an explicit
custom-Store contract extension, not an SDK requirement.

## Interrupted enqueue / recovery

There is deliberately no new outbox or generic workflow platform.

- A directly observed enqueue failure records FAILED for that turn, unless it has
  already moved on or was canceled. Do not revive it automatically.
- A process crash after acceptance but before enqueue can leave SUBMITTED. After
  verifying the queue/worker situation, an operator can enqueue the saved Task,
  principal, Agent, Skill and **exact saved turn_id**. Claim is atomic, so duplicate
  delivery cannot concurrently claim the same submitted turn. Do not replace the
  turn ID or input from a guessed/latest message.
- WORKING is ambiguous after worker loss: business effects may already have occurred.
  Reconcile through the application's own idempotency/business records. Do not reset
  to SUBMITTED or automatically rerun it. A Job retry for a claimed turn is a no-op,
  not proof that business processing completed.
- A waiting question is durable and can receive a new reply after process restart.
  Queue messages hold only safe identifiers, not question/answer bodies or tokens.

The Task-wide `context[:idempotency_key]` is unchanged. New
`context[:execution_turn_id]` permits the app to distinguish turns; it does not
make external services exactly-once. Delayed old Jobs and rescue/outcome writes
cannot replace a newer turn, and canceled/terminal Tasks cannot revive.

## Unchanged behavior / deliberate limits

One-shot Hash/Array/String/FileArtifact output, sync default, Client-only setup,
Direct Message mode and Data key/value rules remain. Continuation is INPUT_REQUIRED
only. No SSE, AUTH_REQUIRED, arbitrary JSON merge, new retry/polling API, production
deployment or new cloud resources. Existing async immediate-return profile stays;
explicit `returnImmediately: true` is the supported async configuration.

Candidate evidence must include actual old records/jobs, migrations on new and
existing databases, PostgreSQL row-lock races, real separate workers, process
restart, actual SDK conversion and both demo TLS runs. Do not infer these from
unit tests alone. See the candidate PR for PASS/NOT_RUN status and exact SHA.
