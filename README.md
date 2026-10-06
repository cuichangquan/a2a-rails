# a2a-rails

Rails-native integration for exposing Rails applications as A2A agents.

> **Status: Core A2A task operations are wired end-to-end through the Protocol Adapter; Configuration and Agent Card generation are next.**

## Current Status

The A2A v1.0 SDK integration path, Gem skeleton, Protocol Adapter, Rails-facing dispatch core, internal Task core, and protocol Task execution path are now runtime-verified.

**Current stage:** Step 15-8 completed — `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` wired to Dispatcher / Task Lifecycle

**Next step:** **Step 15-9 — Implement Configuration plus Agent Card Builder / Validator.**

Step 15-8 adds `Protocol::RequestHandler` and `Protocol::TaskMapper`, connecting the SDK-facing Adapter to the SDK-independent Dispatcher and Task core. Incoming text Messages are normalized to ordinary Ruby Hashes, internal Symbol states remain isolated from the A2A wire format, and internal errors are translated to SDK errors only inside the Protocol Adapter. Real `agent2agent 2.0.0` integration tests cover COMPLETED / REJECTED / FAILED / CANCELED flows, GetTask, ListTasks projection and validation, task-continuation restrictions, content restrictions, and a cancellation race where late Handler completion cannot overwrite `CANCELED`. The current CI has 12 green jobs, and the Gem suite runs 49 tests / 180 assertions with no failures, errors, or skips. See [Draft PR #2](https://github.com/cuichangquan/a2a-rails/pull/2) for implementation and verification details.

Step 15-7 implemented SDK-independent Task state management, Handler result mapping, Artifact mapping, and a thread-safe in-memory Task Store. Step 15-6 implemented `A2A::Rails::Agent`, immutable-ish `Skill` definitions, validation errors, and SDK-independent Handler dispatch. Step 15-5 introduced the first loadable Gem structure and isolated `agent2agent 2.0.0` behind an internal Protocol Adapter. The Step 15-4 isolated spike remains green across Ruby 3.3 / 3.4 / 4.0, Rails 8.0 / 8.1, and a real HTTP server smoke check. See [Step 15 findings](docs/design/sdk-compatibility-spike.md) for evidence and adoption limits.

## Development Progress

- [x] 1. Research A2A Protocol v1.0
- [x] 2. Research Ruby A2A SDKs / Gems
- [x] 3. Research Rails-oriented A2A alternatives
- [x] 4. Define the problem a2a-rails solves
- [x] 5. Define v0.1 scope
- [x] 6. Define terminology
- [x] 7. Define architecture
- [x] 8. Define Ruby SDK boundary
- [x] 9. Public API Design
- [x] 10. Agent Card Design
- [x] 11. Task Lifecycle Design
- [x] 12. Test Strategy
- [x] 13. Gem Structure
- [x] 14. Quick Start Design
- [ ] **15. Start Implementation ← IN PROGRESS**

## v0.1 Direction

v0.1 is **server-first** and focuses on exposing a Rails application as an A2A Agent.

```text
A2A Protocol
     ↓
Ruby A2A SDK
     ↓
a2a-rails
     ↓
Rails Application
     ↓
Business Logic
```

Main principles:

- Do not reimplement the A2A Protocol.
- Focus on Rails integration.
- Keep SDK-specific APIs out of the public API.
- Prefer a small, non-streaming server scope for v0.1.
- Keep a2a-rails independent from ActingFor.

## Design Documents

- [v0.1 Design Decisions](docs/design/v0.1-decisions.md) — current architecture, scope, terminology, SDK boundary, public API, Agent Card design, Task Lifecycle design, and design principles.
- [v0.1 Test Strategy](docs/design/test-strategy.md) — Minitest strategy, test layers, mocking boundaries, Critical E2E cases, and CI policy.
- [v0.1 Gem Structure](docs/design/gem-structure.md) — Gem directory structure, Rails Engine boundary, Protocol Adapter placement, Task components, generators, dummy Rails application, dependencies, and supported Ruby / Rails matrix.
- [v0.1 Quick Start Design](docs/design/quick-start.md) — Echo setup, generator output, A2A v1.0 request, Skill routing, Handler Hash boundary, error experience, and implementation acceptance.

## Quick Start (Design Preview)

The Quick Start is designed but has not been fully implemented or runtime-verified end-to-end through a host Rails application yet. The intended path is:

1. Add `a2a-rails` to an existing Rails application.
2. Generate the initializer and an Echo Agent.
3. Create `Echo::Reply` in the application and declare one `reply` Skill.
4. Register `"EchoAgent"` and start Rails without an explicit Engine mount.
5. Retrieve `/.well-known/agent-card.json`.
6. Send `SendMessage` to `/a2a` with `A2A-Version: 1.0`.
7. Confirm `TASK_STATE_COMPLETED` and an Artifact containing `Echo: Hello`.

The Step 15-8 protocol execution path behind `/a2a` is runtime-verified with the real SDK. Configuration, Agent Card generation, Rails Engine routes/controllers, and generators still need to be connected before the copy-and-paste Rails Quick Start is complete.

See [the complete Quick Start design](docs/design/quick-start.md) for the intended copy-and-paste flow. No database, ActiveJob, authentication, or LLM is needed for this local example.

## Target Developer Experience

The current v0.1 Rails-facing API is:

```ruby
class ShoppingAgent < A2A::Rails::Agent
  name "Shopping Agent"
  description "Search and purchase products"
  version "1.0"

  skill :search_products,
    description: "Search products",
    tags: %w[shopping search],
    handler: Shopping::SearchProducts
end
```

Handler:

```ruby
class Shopping::SearchProducts
  def self.call(message:, context:)
    # Rails business logic
  end
end
```

Registration:

```ruby
A2A::Rails.configure do |config|
  config.agent = "ShoppingAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

v0.1 targets **one public A2A Agent per Rails application**. One Skill dispatches automatically; multiple Skills require an application-owned Router. A2A messages do not contain a standard Skill selector. Handlers receive SDK-independent Ruby Hashes for `message` and `context`; the Handler context includes the selected internal `skill_id`.

For multiple Skills, the Router receives `skills:` as a frozen `Array<Symbol>` containing only declared Skill IDs. It may return a Symbol or String matching one declared Skill. Any unknown selection raises `A2A::Rails::UnknownSkillError`; the Dispatcher never silently falls back to the first Skill.

## Agent Card

The Agent Card is generated automatically from the Rails Agent / Skill DSL.

Standard endpoints:

```text
GET  /.well-known/agent-card.json
POST /a2a
```

For example, with:

```ruby
A2A::Rails.configure do |config|
  config.agent = "ShoppingAgent"
  config.public_base_url = "https://example.com"
end
```

a2a-rails conceptually generates:

```json
{
  "name": "Shopping Agent",
  "description": "Search and purchase products",
  "version": "1.0",
  "supportedInterfaces": [
    {
      "url": "https://example.com/a2a",
      "protocolBinding": "JSONRPC",
      "protocolVersion": "1.0"
    }
  ],
  "capabilities": {
    "streaming": false,
    "pushNotifications": false,
    "extendedAgentCard": false
  },
  "defaultInputModes": ["text/plain"],
  "defaultOutputModes": ["text/plain"],
  "skills": [
    {
      "id": "search_products",
      "name": "Search Products",
      "description": "Search products",
      "tags": ["shopping", "search"]
    }
  ]
}
```

Agent Card design principles:

- Skill IDs are generated from the Skill symbol.
- Skill names are generated automatically and can be overridden.
- `description`, `tags`, and `handler` are required for a Skill.
- `handler` is internal to a2a-rails and is never exposed in the Agent Card.
- `supportedInterfaces` and protocol metadata are generated by the Gem.
- `public_base_url` is used when provided; otherwise the request base URL is used.
- v0.1 defaults to `text/plain` input and output.
- Streaming, Push Notifications, and Extended Agent Cards are not supported in v0.1.
- Invalid Agent definitions are not exposed as partial Agent Cards.

## Task Lifecycle

v0.1 uses A2A standard Task states and keeps lifecycle handling inside the Gem. Internally, Step 15-7 stores SDK-independent Symbol states (`:submitted`, `:working`, `:completed`, `:failed`, `:rejected`, `:canceled`); Step 15-8 converts protocol-specific `TASK_STATE_*` values only at `Protocol::TaskMapper`.

```text
SUBMITTED
    ↓
WORKING
    ├──→ COMPLETED
    ├──→ FAILED
    └──→ REJECTED
```

Handler result mapping:

```text
normal return                  → COMPLETED
A2A::Rails::RejectedTask       → REJECTED
unexpected exception           → FAILED
```

Artifact mapping:

```text
String       → Text Part
Hash / Array → Data Part
nil          → no Artifact
other object → explicit ArtifactMappingError
```

v0.1 Task behavior:

- Task IDs are server-generated.
- Client-provided context IDs are preserved; otherwise the server generates one.
- Task lifecycle and state transitions are internal to a2a-rails.
- Terminal states are immutable; late completion cannot overwrite `COMPLETED`, `FAILED`, `REJECTED`, or `CANCELED`.
- The default Task Store is the thread-safe in-memory `Task::MemoryStore`.
- Stored values are returned as copies so response shaping cannot mutate persisted Task state accidentally.
- `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` are wired through the real SDK in Step 15-8.
- `ListTasks` supports context/state/timestamp filters, newest-first stable ordering, page sizes 1–100, and opaque snapshot pagination.
- `CancelTask` transitions non-terminal Tasks atomically to `CANCELED`; synchronous Handler completion cannot overwrite it. Cancellation does not interrupt Handler execution or undo business side effects.
- v0.1 accepts text Message Parts for Handler execution; unsupported content is rejected at the protocol boundary.
- Continuing an existing Task via `message.taskId` is not supported in v0.1.
- `INPUT_REQUIRED` and `AUTH_REQUIRED` are out of scope for v0.1.
- Unexpected exceptions are logged internally and exposed as the generic `Task execution failed` message.
- Task history means A2A Message history, not state transition history.

The in-memory Task Store is intended for development and simple synchronous workloads. Tasks and pagination cursors are process-local; they are not guaranteed to survive Rails process restarts or be shared across multiple processes.

## Test Strategy

v0.1 uses **Minitest** and separates tests into four layers.

```text
4. Protocol E2E / Smoke Tests
3. Rails Integration Tests
2. Adapter Contract Tests
1. Core Unit Tests
```

Core principles:

- Unit Tests cover Agent / Skill DSL, Configuration, Dispatcher, Task Lifecycle, Artifact Mapping, and Task Store.
- Protocol Adapter Unit Tests mock the Ruby A2A SDK.
- Adapter Contract Tests and Critical E2E use the real Ruby A2A SDK.
- Rails Integration Tests use a dummy Rails application.
- A2A Protocol behavior and SDK internals are not re-tested by a2a-rails.
- Gem-internal components are not mocked in Critical E2E tests.

Critical E2E cases for v0.1:

```text
1. Agent Card retrieval
2. SendMessage → COMPLETED
3. SendMessage → REJECTED
4. SendMessage → FAILED
5. GetTask → stored Task retrieval
6. ListTasks → filters, pagination, history, artifacts
7. CancelTask → accepted cancellation / terminal rejection
8. Version and disabled Capability errors
```

Step 15-8 now exercises the Task-operation subset above through the real Ruby SDK, including a concurrent CancelTask race. Full host-Rails Critical E2E remains pending the Engine / route / controller layer.

CI runs Unit, Adapter Contract, Rails Integration, and Critical E2E tests on pull requests and `main` pushes. Release builds require all supported Ruby / Rails matrix combinations to be green.

See [v0.1 Test Strategy](docs/design/test-strategy.md) for details.

## Gem Structure

v0.1 keeps Gem core behavior under `lib/a2a/rails` and keeps the Rails HTTP layer thin.

```text
lib/a2a/rails/
├── agent.rb
├── skill.rb
├── dispatcher.rb
├── configuration.rb
├── agent_card/
├── task/
└── protocol/
```

Key decisions:

- Rails Engine / controllers / routes are only the Rails integration layer.
- SDK-specific behavior is isolated behind `Protocol::Adapter` and `Protocol::Agent2AgentAdapter`.
- Step 15-5 implemented the initial Gem skeleton and Protocol Adapter.
- Step 15-6 implemented `Agent`, `Skill`, errors, and `Dispatcher`; single-Skill auto-dispatch and explicit multi-Skill Router selection are runtime-tested.
- `name "..."` stores the A2A display name without replacing Ruby's normal zero-argument `Class#name` behavior.
- Router `skills:` is a frozen `Array<Symbol>` of declared Skill IDs; unknown selections raise `UnknownSkillError`.
- Step 15-7 implements `Task::Lifecycle`, `Task::ResultMapper`, `Task::ArtifactMapper`, the `Task::Store` contract, and thread-safe `Task::MemoryStore`.
- Step 15-8 adds `Protocol::RequestHandler` and `Protocol::TaskMapper` and wires Dispatcher / Task Lifecycle to `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` through the real SDK.
- A2A camelCase fields, `TASK_STATE_*` values, SDK schema objects, and SDK error classes remain Protocol-layer concerns; Handler and Task core APIs remain SDK-independent.
- Static Agent / Skill validation occurs before Task creation; Handler execution failures after a Task starts map through the Task lifecycle.
- The default v0.1 Task Store is in-memory.
- v0.1 generators are limited to `install` and `agent`.
- `install` creates only the initializer with a generic `"YourAgent"` placeholder.
- `agent` creates only the Agent scaffold; it does not reference a nonexistent Handler or register the Agent automatically.
- Registered Agent validation happens when A2A endpoints are used; incomplete A2A configuration does not fail host Rails boot.
- Rails integration tests use a minimal `test/dummy` application.
- ActiveRecord and ActiveJob are not required dependencies.
- v0.1 targets Ruby `>= 3.3` and Rails `>= 8.0, < 8.2`; the SDK dependency graph cannot resolve on Ruby 3.2.
- The implementation currently depends on `agent2agent ~> 2.0.0`, `json < 3`, `rack >= 3.0, < 4`, and `railties >= 8.0, < 8.2`.
- The SDK's server triage logger can emit the Rack environment including parsed request bodies; the production Rails-facing integration must prevent sensitive request/body/auth data from being exposed through SDK logging.

See [v0.1 Gem Structure](docs/design/gem-structure.md) for details.

## v0.1 Scope

Included:

- Rails integration
- `A2A::Rails::Agent`
- Skill DSL
- Handler dispatch
- Agent Card generation
- `/.well-known/agent-card.json`
- `POST /a2a`
- minimum Task lifecycle
- `GetTask`, `ListTasks`, `CancelTask`
- `A2A-Version: 1.0` validation
- in-memory Task Store
- Rails Engine / Routes
- Configuration
- Generator
- Rails Logging
- Test support

Not included in v0.1:

- A2A Client
- ActiveRecord Task Store
- ActiveJob Task execution
- SSE / BiDi Streaming
- Push Notifications
- gRPC
- Human-in-the-loop
- `INPUT_REQUIRED` / `AUTH_REQUIRED` flows
- Agent Registry / Marketplace
- OAuth Server
- Authorization Engine
- ActingFor integration
- Admin UI
- LLM Agent Framework
- Orchestration Framework

