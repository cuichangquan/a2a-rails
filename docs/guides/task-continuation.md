# Ask for input and resume the same Task

This is the **0.5.0 candidate**, not a released RubyGems version. Use the reviewed
candidate artifact or exact source SHA recorded in its PR. Existing one-shot
Handlers and Client DTOs keep their contracts.

```ruby
class ReportHandler
  def self.call(message:, context:)
    # These are application-owned rules, not arbitrary JSON merge behavior.
    criteria = context.fetch(:history).each_with_object({}) do |entry, result|
      next unless entry[:role].to_s == "user"
      entry.fetch(:parts).each do |part|
        next unless part[:data].is_a?(Hash)
        result.merge!(part[:data].slice("year", "month", "department_id"))
      end
    end
    unless criteria.key?("department_id")
      return A2A::Rails::InputRequired.new("Which department?",
        data: {"missing_fields" => ["department_id"]})
    end
    # Recheck current business permissions and validate all fields here.
    Reports.generate(criteria, principal_id: context.fetch(:principal_id))
  end
end
```

The existing `message:` argument is this turn's input. `context[:history]` is an
isolated copy of all retained messages, including current input and previous agent
questions. Ruby envelope keys are symbols; persisted role values may be strings,
so compare `role.to_s`. JSON Data keys/values remain unchanged. `execution_turn_id`
is unique per accepted turn. `idempotency_key` remains the Task ID, so use an
application-specific turn key for distinct business operations when appropriate.

`InputRequired.new(text, data: optional_hash)` returns a normal non-terminal
outcome. The text must be nonempty; optional Data is a JSON object with string keys
and finite numbers. It is not an exception and not a special Hash convention.
Questions are persisted as agent messages and also returned in `status.message`.
Direct Message mode cannot pause: this result yields invalid-agent-response and
creates no Task. Declare skill output modes for both text and JSON if using both.

## Existing Client API

Send the next answer with the Task ID using the existing Message/SendMessage API.
Read `TASK_STATE_INPUT_REQUIRED`, `status.message`, `id` and `contextId` from the
Task DTO; it is waiting, not complete. A taskId-only answer infers contextId. If
both are supplied they must match. The saved Agent and Skill are reused; Router
is not called again. An app still validates permissions on every execution.
No polling/retry API, nonstandard operation or extra Agent Card capability is added.

Only waiting Tasks accept new answers. WORKING and SUBMITTED reject new answers (JSON-RPC InvalidParams, -32602);
terminal Tasks return standard UnsupportedOperation (-32004). Legacy Tasks without saved execution
metadata return UnsupportedOperation (-32004), not a newly created Task. Missing
and foreign-owned IDs both return TaskNotFound (-32001). Authentication still runs
before request handling. `taskId`, `contextId`, and Data IDs are not credentials.

Accepted continuation messageIds are deduplicated within the retained Task history:
identical content returns the current Task without rerunning; changed content is
InvalidParams. The first request's ID is not a continuation receipt. New Task
creation is not generally idempotent. Do not automatically retry unknown network
outcomes. A new messageId alone does not identify which question the answer belongs
to; validate question correlation in the application if delayed answers matter.

## Bounds, persistence and operations

`historyLength` only limits the response. Even zero leaves internal input intact.
Both built-in stores enforce `max_task_history_entries` (default 100), counting
inputs and questions. Acceptance reserves room for another question and rejects
before execution when full; cancel/start a new Task explicitly. Nothing is silently
truncated. An unexpectedly unpersistable question fails its own turn.

MemoryStore loses all Tasks on process restart. ActiveRecordStore survives restart;
run the additive migration and choose a stable page-token secret. Waiting Tasks
have no expiration by default; set `task_input_required_retention` in seconds to
bound them with existing `prune_expired` maintenance. Expired waiting Tasks may be
removed; never present pruning as canceling external work. Retention must fit the
user-visible answering window. Cleanup is explicit, not performed inside requests.

Async jobs finish when a question is recorded and do not hold a connection/worker
while waiting. This Gem's existing async profile immediately returns SUBMITTED;
use `configuration.returnImmediately: true`. Blocking false/unset semantics from
the full A2A standard are not implemented; this limitation predates continuation.
For sync, SendMessage returns the resulting Task normally.

See [upgrade/recovery](../release/upgrading-v0.4.0-to-v0.5.md) and
[design/boundary](../design/task-continuation.md). These are narrow continuation
contracts, not external exactly-once guarantees or full A2A certification.
