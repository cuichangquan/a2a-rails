# Task continuation (0.5.0 candidate design)

## Public contract

```ruby
return A2A::Rails::InputRequired.new("Which department?", data: {"field" => "department_id"})
```

An explicit Gem-owned result is simpler than an exception for normal control flow.
Plain Hash/Array results retain their 0.4.0 meaning regardless of keys such as
`state`. `message:` is the current answer; `context[:history]` is a copied ordered
history of original input, agent questions and answers (including current input).
Applications combine selected fields and recheck business permissions each turn.
`context[:execution_turn_id]` identifies one execution; `idempotency_key` retains
its Task-wide meaning. No SDK classes in Handler, Store or Job contracts.

States: SUBMITTED → WORKING → INPUT_REQUIRED → SUBMITTED → WORKING, repeating
as needed; WORKING can also complete/fail/reject. Waiting Tasks can be canceled.
Terminal states never revive. Only INPUT_REQUIRED accepts a new answer, and it
resumes the saved Agent/Skill, never the router. Direct Message cannot wait and
returns the existing invalid-agent-response protocol error without creating a Task.

## Protocol and scope

Baseline: [A2A v1.0.0](https://a2a-protocol.org/v1.0.0/specification/), sections
3.2.2, 3.3, 3.4.3 and TaskState. `taskId` without `contextId` uses the saved
context; mismatches are invalid parameters. Missing/foreign Tasks are identical.
INPUT_REQUIRED is not terminal; `historyLength` projects responses only.
SendMessage now honors its standard `configuration.historyLength` location; the
old handler incorrectly looked at top-level and the SDK discarded that field.
GetTask/ListTasks continue using top-level historyLength. This narrow correctness
fix is necessary so hidden response history does not obstruct continuation.
A repeated continuation messageId with identical normalized content returns the
current Task without appending or executing; changed content is invalid parameters.
This bounded optional dedupe is a product guarantee, not general SendMessage
idempotency. New replies to terminal Tasks return standard UnsupportedOperation (-32004).
WORKING/SUBMITTED replies are outside the supported profile (InvalidParams -32602).
A new ID cannot reliably distinguish an answer to a previous question
from an answer to the current question; apps needing correlation must validate it.

The existing async profile returns SUBMITTED immediately even when
`returnImmediately` is omitted. The standard says false/unset waits until terminal
or INPUT_REQUIRED; retain and document this existing limited profile rather than
silently changing 0.4.0 queue behavior. Callers of async Tasks must explicitly use
`returnImmediately: true`; this release does not claim full protocol conformance.

## Persistence and execution

A saved execution envelope records Agent, Skill, mode, turn UUID and messageId.
Store operations atomically authorize owner, validate context/state, dedupe, append
answer and install the new turn under a mutex or DB row lock. Handler runs outside
the lock. Every claim and outcome compares the turn ID, so stale Jobs/rescue paths
cannot finalize a later turn. Jobs select their own saved messageId, not latest
input or history.first. History stores JSON data unchanged. Bounds reject, never
truncate required context; response-history bounds are separate.

0.4.0 Tasks/Jobs remain readable/executable as legacy records with no execution
metadata; they cannot be guessed into resumable Tasks. An additive migration is
required for durable continuation. Stop/drain old workers, migrate, deploy new
workers, then enable continuation; mixed workers cannot safely process new jobs.
See the upgrade guide for recovery/rollback details. Persistence before enqueue
is not an atomic outbox: observed enqueue failure fails the same turn; a crash
between save and enqueue can leave SUBMITTED and needs explicit operator recovery.
Do not automatically rerun ambiguous WORKING or promise external exactly-once.

## Verification status

This is the intended contract, not completed evidence. Candidate readiness requires
Store/Job/Adapter contracts, PostgreSQL concurrency, separate workers, restart,
0.4.0 upgrade, Python interop and both demo TLS checks, plus independent review.
