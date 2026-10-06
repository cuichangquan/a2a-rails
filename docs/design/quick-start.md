# a2a-rails v0.1 Quick Start Design

> **Status: Step 14 design complete. Step 15-7 implements the Agent / Skill / Dispatcher and internal Task core; generators, Rails HTTP integration, protocol execution wiring, and the full Quick Start are not runtime-verified yet.**

This document fixes the first-time developer experience for an existing Rails application. The example uses Echo to keep the gem independent of any business domain.

## 1. Golden Path

1. Add the gem.
2. Generate the initializer.
3. Generate one Agent.
4. Create one application-owned Handler and register one Skill.
5. Register the Agent by class-name string and start Rails.
6. Retrieve the Agent Card (intermediate success).
7. Send a message and receive a completed Task with an Echo Artifact (final success).

No database, ActiveJob, authentication, LLM, streaming, or explicit Engine mount is required for this local Quick Start.

## 2. Generator Contract

`install` creates only `config/initializers/a2a_rails.rb`:

```ruby
A2A::Rails.configure do |config|
  config.agent = "YourAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

`agent echo` creates only `app/agents/echo_agent.rb`:

```ruby
class EchoAgent < A2A::Rails::Agent
  name "Echo Agent"
  description "TODO"
  version "1.0"

  # Add at least one skill.
end
```

The generated Agent does not reference a nonexistent Handler. It is a scaffold, not a valid public Agent until a Skill is added. Generators do not create Handlers, controllers, routes, migrations, Task Stores, jobs, or authentication settings. They do not automatically register the generated Agent. Handler placement is an application choice; `app/services` below is an example.

## 3. README Quick Start

The following is the intended post-implementation copy-and-paste path. `bundle add` is not evidence that this project has been released.

### Add and install

```bash
bundle add a2a-rails
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent echo
mkdir -p app/services/echo
```

### Create the Handler

Create `app/services/echo/reply.rb`:

```ruby
class Echo::Reply
  def self.call(message:, context:)
    text = message[:parts]
      .filter_map { |part| part[:text] }
      .join("\n")

    "Echo: #{text}"
  end
end
```

### Define the Skill

Replace `app/agents/echo_agent.rb` with:

```ruby
class EchoAgent < A2A::Rails::Agent
  name "Echo Agent"
  description "Echo messages"
  version "1.0"

  skill :reply,
    description: "Echo a message",
    tags: %w[echo],
    handler: Echo::Reply
end
```

A single Skill is selected automatically. No Router is needed for this example.

### Register the Agent

Replace `config/initializers/a2a_rails.rb` with:

```ruby
A2A::Rails.configure do |config|
  config.agent = "EchoAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

For this localhost example, leave `A2A_PUBLIC_BASE_URL` unset or set it to `http://localhost:3000`. An explicit base URL takes precedence over the request base URL and must not contain `/a2a`.

```bash
bin/rails server
```

No change to `config/routes.rb` is required.

### Check the Agent Card

```bash
curl -sS http://localhost:3000/.well-known/agent-card.json \
  -H "A2A-Version: 1.0"
```

Confirm HTTP 200, Agent name `Echo Agent`, Skill ID `reply`, and a JSON-RPC supported interface with protocol version `1.0` pointing to `http://localhost:3000/a2a`.

### Send the First Message

```bash
curl -sS -X POST http://localhost:3000/a2a \
  -H "Content-Type: application/json" \
  -H "A2A-Version: 1.0" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "SendMessage",
    "params": {
      "message": {
        "messageId": "msg-1",
        "role": "ROLE_USER",
        "parts": [{"text": "Hello"}]
      }
    }
  }'
```

The request supplies a Message ID and omits Task ID and Context ID. The server generates the Task ID and Context ID. No standard Skill ID field is sent.

Default v0.1 execution is synchronous. The default A2A send configuration waits for a terminal or interrupted state; this Echo example completes within the same request.

Illustrative success response (IDs and optional fields vary):

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "result": {
    "task": {
      "id": "task-generated-id",
      "contextId": "context-generated-id",
      "status": {"state": "TASK_STATE_COMPLETED"},
      "artifacts": [
        {
          "artifactId": "artifact-generated-id",
          "parts": [{"text": "Echo: Hello"}]
        }
      ]
    }
  }
}
```

Success means `result.task.status.state` is `TASK_STATE_COMPLETED`, Task ID and Context ID are present, and a Text Part in the Task Artifacts contains `Echo: Hello`. Exact IDs, timestamps, optional fields, and Artifact metadata are not fixed fixtures.

## 4. Skill Routing

A2A v1.0 `SendMessageRequest` and `Message` do not define a standard `skill_id`. Agent Card Skills advertise capabilities; they are not protocol method selectors.

- One Skill: dispatch automatically to its Handler.
- Multiple Skills: require an application-owned Router.
- Do not silently select the first Skill.
- Do not introduce a required custom Skill selector into the Quick Start request.
- a2a-rails does not supply LLM routing or business routing rules.

Router API:

```ruby
class ShoppingAgent < A2A::Rails::Agent
  router Shopping::AgentRouter

  skill :search_products,
    description: "Search products",
    tags: %w[shopping search],
    handler: Shopping::SearchProducts

  skill :purchase_product,
    description: "Purchase products",
    tags: %w[shopping purchase],
    handler: Shopping::PurchaseProduct
end
```

```ruby
class Shopping::AgentRouter
  def self.call(message:, context:, skills:)
    # skills is a frozen Array<Symbol> of declared Skill IDs.
    :search_products
  end
end
```

The Dispatcher validates the selected ID against declared Skills. `skills:` is a frozen `Array<Symbol>` containing only declared Skill IDs. The Router may return a matching Symbol or String. An unknown selection raises `A2A::Rails::UnknownSkillError`; the Dispatcher never silently falls back to another Skill. The Router receives execution context before Skill selection, and `skill_id` is added to a new Handler context after selection without mutating the incoming context.

## 5. Handler Boundary

Keep the existing interface:

```ruby
def self.call(message:, context:)
end
```

The Protocol Adapter supplies ordinary Ruby Hashes rather than SDK-specific objects. Schema keys use symbols; arbitrary metadata/data payloads preserve their values and keys.

Quick Start Message:

```ruby
{
  message_id: "msg-1",
  role: :user,
  parts: [{ text: "Hello", media_type: "text/plain" }],
  metadata: {}
}
```

`ROLE_USER` maps to `:user`; `ROLE_AGENT` maps to `:agent`. Missing Message metadata normalizes to `{}`. For the text-only Quick Start, an omitted Part media type normalizes to `text/plain`.

Handler context:

```ruby
{
  task_id: "task-generated-id",
  context_id: "context-generated-id",
  skill_id: :reply
}
```

`skill_id` is internal dispatch information, not a standard A2A request field. Client-provided Context IDs are preserved; otherwise the server generates one. The Echo Handler may ignore context.

Do not introduce public `A2A::Rails::Message`, `Context`, or `TextPart` classes in v0.1. Task and Artifact conversion remains internal. A String return becomes a Text Part Artifact.

Step 15-7 now implements the internal Task representation and result boundary. Internal Task hashes use Symbol keys and Symbol states; A2A enum/string conversion remains the Protocol Adapter's responsibility. `Task::Lifecycle` owns creation and state transitions but deliberately does not invoke Handlers directly, so Agent/Router configuration failures remain separate from FAILED business Tasks.

## 6. First-Time Error Experience

Adding the gem or running a generator must not fail Rails boot merely because the A2A Agent is unregistered or incomplete. Resolve and validate the registered Agent when an A2A endpoint is used, respecting Rails autoload/reload. This does not promise to suppress syntax errors in application-owned Ruby code.

| Cause | Developer-facing error/log | Client behavior |
| --- | --- | --- |
| `config.agent` is nil or cannot be resolved | `ConfigurationError`: no registered Agent could be resolved | No partial Agent Card or Handler dispatch |
| Agent has zero Skills | `ConfigurationError`: `EchoAgent must define at least one skill` | No partial Agent Card or Handler dispatch |
| Handler lacks `.call` | `InvalidHandlerError`: `Handler Echo::Reply must respond to .call` | No Handler dispatch |
| Multiple Skills without Router | `ConfigurationError`: Agent defines multiple Skills but no Router is configured | No arbitrary Skill fallback |
| Handler raises an unexpected exception | Detailed exception in Rails logger | Task state `TASK_STATE_FAILED` with a generic message |

Configuration failures occur before business execution; they do not masquerade as failed Handler Tasks. Agent Card validation failures return a generic HTTP 500, consistent with the Agent Card design. A2A request failures use the SDK/Adapter error boundary. Never expose Ruby class names, stack traces, or raw unexpected exception messages to clients.

## 7. Acceptance and Next Step

Step 14 is complete as a design decision. Step 15-7 now runtime-verifies the Agent / Skill / Dispatcher subset plus the internal Task core. Full Quick Start implementation acceptance still requires:

- Generator output matches the two-file contract and contains no dangling Handler reference.
- An unconfigured or incomplete Agent does not break host Rails boot.
- The exact Echo path produces a valid Agent Card and a completed Task via the real SDK.
- SDK values normalize into the documented Message and Handler context.
- Single-Skill dispatch and explicit multi-Skill routing are covered.
- Configuration errors and Handler exceptions follow the separate behaviors above.
- README examples, contract tests, and Critical E2E use A2A v1.0 method names and wire shapes.

Implemented through Step 15-7:

- Agent metadata / Skill DSL.
- Skill validation and callable Handler validation.
- Single-Skill automatic dispatch.
- Multi-Skill Router dispatch with a frozen Symbol ID collection.
- Unknown Router selection via `UnknownSkillError`.
- Handler `skill_id` context injection without mutating incoming context.
- Ruby `Class#name` behavior remains intact even though `name "..."` is used as the display-name DSL.
- Task creation and `SUBMITTED` / `WORKING` / terminal-state transitions.
- String / Hash / Array / nil Handler result mapping to internal Artifacts.
- Explicit `ArtifactMappingError` for unsupported result types.
- Generic FAILED client message plus detailed internal logging.
- Atomic cancellation and terminal-state overwrite protection.
- Thread-safe in-memory Task storage with deep-copy reads.
- `ListTasks` filtering, stable newest-first ordering, and opaque snapshot pagination.

**Next: Step 15-8 — Connect Dispatcher + Task Lifecycle to `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask`, and map the internal Task representation through the Protocol Adapter.**

## Official References

- [A2A specification: JSON-RPC binding and versioning](https://github.com/a2aproject/A2A/blob/main/docs/specification.md)
- [A2A schema: Message, Part, Task, Artifact, SendMessageRequest/Response](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto)
