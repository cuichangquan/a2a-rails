# a2a-rails

Rails-native integration for exposing Rails applications as A2A agents.

> **Status: Rails Engine HTTP integration is implemented and runtime-verified; generators and the final copy-and-paste Quick Start are next.**

## Current Status

The A2A v1.0 SDK integration path, Gem skeleton, Protocol Adapter, Rails-facing dispatch core, internal Task core, protocol Task execution path, Configuration, Agent Card generation, and host-Rails HTTP endpoints are now runtime-verified.

**Current stage:** Step 15-10 completed — Rails Engine + standard routes + thin controllers

**Next step:** **Step 15-11 — Implement the `install` / `agent` generators and complete the copy-and-paste host-Rails Quick Start.**

Step 15-10 adds an automatically mounted Rails Engine, thin API controllers, and a shared internal Runtime for `GET /.well-known/agent-card.json` and `POST /a2a`. The Runtime keeps the in-memory Task Store across HTTP requests while resolving the configured Agent lazily for each endpoint use. A real minimal host Rails application verifies Agent Card retrieval, `SendMessage → COMPLETED`, and a later `GetTask` request retrieving the Task created by the previous HTTP request. Explicit `public_base_url` precedence is also verified. SDK `A2A::Server::Triage` info logging is suppressed only around each adapter call so full Rack environments, request bodies, and auth-sensitive data are not emitted; the previous Console logger state is restored afterward. The current CI has 12 green jobs, and the Gem suite runs 69 tests / 237 assertions with no failures, errors, or skips. See [Draft PR #4](https://github.com/cuichangquan/a2a-rails/pull/4) for implementation and verification details.

Step 15-9 implemented lazy Configuration and Agent Card generation. Step 15-8 wired `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` through the real SDK. Step 15-7 implemented SDK-independent Task state management, Handler result mapping, Artifact mapping, and a thread-safe in-memory Task Store. Step 15-6 implemented `A2A::Rails::Agent`, immutable-ish `Skill` definitions, validation errors, and SDK-independent Handler dispatch. Step 15-5 introduced the first loadable Gem structure and isolated `agent2agent 2.0.0` behind an internal Protocol Adapter. The Step 15-4 isolated spike remains green across Ruby 3.3 / 3.4 / 4.0, Rails 8.0 / 8.1, and a real HTTP server smoke check. See [Step 15 findings](docs/design/sdk-compatibility-spike.md) for evidence and adoption limits.

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

The manual host-Rails HTTP path is now runtime-verified. The intended copy-and-paste path is:

1. Add `a2a-rails` to an existing Rails application.
2. Generate the initializer and an Echo Agent.
3. Create `Echo::Reply` in the application and declare one `reply` Skill.
4. Register `"EchoAgent"` and start Rails without an explicit Engine mount.
5. Retrieve `/.well-known/agent-card.json`.
6. Send `SendMessage` to `/a2a` with `A2A-Version: 1.0`.
7. Confirm `TASK_STATE_COMPLETED` and an Artifact containing `Echo: Hello`.

Step 15-10 runtime-verifies steps 4–7 through an actual minimal host Rails application, including a second HTTP request that retrieves the Task created by the first request. The remaining Quick Start gap is implementing the `install` / `agent` generators and verifying the exact generated files against this working HTTP path.

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

a2a-rails generates:

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

Agent Card behavior now runtime-verified:

- Skill IDs are generated from the Skill symbol.
- Skill names are generated automatically and can be overridden.
- `description`, `tags`, and `handler` are required for a Skill.
- Optional Skill `examples`, `input_modes`, and `output_modes` map to A2A Agent Card fields.
- `handler` is internal to a2a-rails and is never exposed in the Agent Card.
- `supportedInterfaces` and protocol metadata are generated by the Gem.
- `public_base_url` is used when provided; otherwise the request base URL is used.
- v0.1 defaults to `text/plain` input and output.
- Streaming, Push Notifications, and Extended Agent Cards are fixed as unsupported in v0.1.
- Invalid Agent definitions are rejected before a Card is returned.
- The generated Card passes the real `agent2agent 2.0.0` Agent Card schema.
- Step 15-10 verifies the generated Card from the actual `/.well-known/agent-card.json` Rails endpoint.

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
- Step 15-10 keeps one `Task::MemoryStore` in the Gem Runtime so separate HTTP requests in the same process can use `GetTask` / `ListTasks` / `CancelTask` against earlier Tasks.

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

- Unit Tests cover Agent / Skill DSL, Configuration, Agent Card Builder / Validator, Dispatcher, Task Lifecycle, Artifact Mapping, and Task Store.
- Protocol Adapter Unit Tests mock the Ruby A2A SDK.
- Adapter Contract Tests and Critical E2E use the real Ruby A2A SDK.
- Rails Integration Tests use a minimal host Rails application.
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

Step 15-8 exercises the Task-operation subset above through the real Ruby SDK, including a concurrent CancelTask race. Step 15-9 adds a real-SDK contract test for generated Agent Card schema validity. Step 15-10 adds an isolated real host-Rails smoke path for Engine auto-mount, Agent Card retrieval, `SendMessage`, cross-request `GetTask`, and base-URL behavior. The exact generator-backed copy-and-paste Quick Start remains for Step 15-11.

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
├── runtime.rb
├── engine.rb
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
- Step 15-9 adds lazy `Configuration`, `AgentCard::Builder`, `AgentCard::Validator`, and optional Skill Agent Card metadata.
- Step 15-10 adds the automatically mounted Rails Engine, standard routes, thin API controllers, and a process-local Runtime that owns the default Task Store.
- Agent resolution happens when an A2A endpoint needs it, not when the initializer assigns `config.agent`, preserving Rails autoload/reload compatibility.
- Agent Card generation remains SDK-independent internally; the real SDK schema is used as a contract test rather than leaked into the public API.
- A2A camelCase fields, `TASK_STATE_*` values, SDK schema objects, and SDK error classes remain Protocol-layer concerns; Handler and Task core APIs remain SDK-independent.
- Static Agent / Skill validation occurs before Task creation; Handler execution failures after a Task starts map through the Task lifecycle.
- The default v0.1 Task Store is in-memory and shared across requests within one Runtime/process.
- Gem-internal controllers are explicitly loaded by the Engine; application-owned Agent/Handler classes remain lazy-resolved through Rails.
- `A2A::Server::Triage` info logging is raised to WARN only for the current adapter call/fiber and restored afterward, preventing full Rack env/request-body logging without globally muting Console.
- v0.1 generators are limited to `install` and `agent`.
- `install` creates only the initializer with a generic `"YourAgent"` placeholder.
- `agent` creates only the Agent scaffold; it does not reference a nonexistent Handler or register the Agent automatically.
- Registered Agent validation happens when A2A endpoints are used; incomplete A2A configuration does not fail host Rails boot.
- Rails HTTP smoke testing boots a minimal host application in an isolated subprocess so Rails global application/logger state does not leak into core unit tests.
- ActiveRecord and ActiveJob are not required dependencies.
- v0.1 targets Ruby `>= 3.3` and Rails `>= 8.0, < 8.2`; the SDK dependency graph cannot resolve on Ruby 3.2.
- The implementation currently depends on `agent2agent ~> 2.0.0`, `actionpack >= 8.0, < 8.2`, `json < 3`, `rack >= 3.0, < 4`, and `railties >= 8.0, < 8.2`.
- Known upstream SDK warnings remain under warning-enabled tests, but Step 15-10 prevents the SDK Triage info log from exposing full request environments.

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
