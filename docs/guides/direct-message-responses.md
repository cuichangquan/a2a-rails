# Direct Message responses (unreleased main, Step 17-4)

> **Not available in published RubyGems v0.1.0.** This feature was merged to main via [PR #24](https://github.com/cuichangquan/a2a-rails/pull/24) and verified against real Ruby SDK/official TCK tests; it has **not** been published to RubyGems. It does not make the Gem production ready; see [production security](production-security.md).

A2A Protocol v1.0 [Send Message](https://a2a-protocol.org/v1.0.0/specification/#311-send-message) allows either a `Task` or a direct `Message` for simple interactions. The Gem retains the existing synchronous Task response by default. A Rails Agent can explicitly choose to return direct Messages without starting or persisting a Task.

## Simple, always-direct Agent

```ruby
class EchoAgent < A2A::Rails::Agent
  name "Echo Agent"
  description "Directly replies to text messages"
  version "1.0"

  response_mode :message # opt-in; default is :task

  skill :reply,
    description: "Echo a message",
    tags: %w[echo],
    handler: Echo::Reply
end

class Echo::Reply
  def self.call(message:, context:)
    "Echo: #{'#{'}message.dig(:parts, 0, :text)}"
  end
end
```

A successful `SendMessage` returns an SDK-validated `result.message` containing `messageId`, `role: "ROLE_AGENT"`, `contextId`, and `parts` (here, a Text Part). It does **not** contain `result.task` or a Task ID. `GetTask` and `ListTasks` will not find such a reply.

## Mixed use: select a mode per incoming request

```ruby
response_mode ->(message:) {
  message.dig(:parts, 0, :text)&.start_with?("ping") ? :message : :task
}
```

The callback is **application-owned** and receives the *normalized* inbound message Hash. It must return `:message` or `:task` and must not trust a client-provided `messageId`, metadata, or other field as an authorization signal. Choose a mode based on the host's own business rules. The selection happens before Task creation, so `Message` replies never leave placeholder Task records. A single Agent-level policy currently applies to all its Skills.

## Handler contract and limitations

- Supported outputs are unchanged: `String` becomes a Text Part; `Hash` or `Array` becomes a Data Part; `A2A::Rails::FileArtifact.bytes/.url` becomes a File Part. The Gem reuses its existing Artifact output conversion internally; direct results are delivered as Message Parts, not as an Artifact.
- Unlike Task mode, **`nil` is not valid for a direct Message** because a direct Message must carry content. An unsupported result type or Handler exception yields a sanitized `InvalidAgentResponseError` (JSON-RPC `-32006`), never an application exception message.
- Direct Message Handlers receive `context: { task_id: nil, context_id: "...", skill_id: ... }`. A missing inbound `contextId` is replaced with a newly generated UUID. The context ID is **not** proof of identity or access control.
- Task mode retains `context[:task_id]` and its current lifecycle, cancellation, owner-scoped storage and error behavior. Code requiring Task state, polling, cancellation or persistence should keep the default `:task` mode.
- The host must still implement real caller authentication, business authorization, rate limits, input controls and output privacy. Message mode is not a security bypass or a streaming mode.

## Verification

`test/protocol/request_handler_integration_test.rb` exercises both response union variants via the real `agent2agent` SDK, including Message-only storage absence, context IDs, text/data/file outputs, mixed mode and sanitized failures. The pinned [official JSON-RPC MUST TCK](../testing/official-a2a-tck.md) uses an isolated loopback Agent fixture for the direct-Message scenario. The TCK is **not** a full protocol conformance certificate.
