# a2a-rails

Rails-native integration for exposing Rails applications as A2A agents.

> **Status: SDK spike verified — the Rails gem is not implemented yet.**

## Current Status

The v0.1 design is defined. Step 15 now verifies the published SDK before implementing the Rails gem.

**Current stage:** Step 15-4 completed — `agent2agent 2.0.0` runtime compatibility spike

**Next step:** **Step 15-5 — Implement the Gem skeleton and Protocol Adapter.**

The isolated spike passed all 9 CI jobs: Ruby 3.3 / 3.4 / 4.0, Rails 8.0 / 8.1, and a real HTTP server smoke check. The SDK contract suite has 17 tests / 231 assertions; Rails integration has 1 test / 9 assertions per combination. It covers Agent Card, Echo, `GetTask`, `ListTasks`, `CancelTask`, version validation, capability errors, and exact Rails routes. See [Step 15 findings](docs/design/sdk-compatibility-spike.md) for evidence and adoption limits.

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

The Quick Start is designed but has not been implemented or runtime-verified. The intended path is:

1. Add `a2a-rails` to an existing Rails application.
2. Generate the initializer and an Echo Agent.
3. Create `Echo::Reply` in the application and declare one `reply` Skill.
4. Register `"EchoAgent"` and start Rails without an explicit Engine mount.
5. Retrieve `/.well-known/agent-card.json`.
6. Send `SendMessage` to `/a2a` with `A2A-Version: 1.0`.
7. Confirm `TASK_STATE_COMPLETED` and an Artifact containing `Echo: Hello`.

See [the complete Quick Start design](docs/design/quick-start.md) for copy-and-paste examples intended for use after implementation. No database, ActiveJob, authentication, or LLM is needed for this local example.

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

v0.1 uses A2A standard Task states and keeps lifecycle handling inside the Gem.

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
```

v0.1 Task behavior:

- Task IDs are server-generated.
- Client-provided context IDs are preserved; otherwise the server generates one.
- Task lifecycle and state transitions are internal to a2a-rails.
- The default Task Store is in-memory.
- `GetTask` is supported.
- `ListTasks` and `CancelTask` are included in the v0.1 design (Step 15 revision).
- Accepted cancellation reaches `CANCELED`; synchronous handler completion must not overwrite it. Cancellation does not interrupt handler execution or undo business side effects.
- `INPUT_REQUIRED` and `AUTH_REQUIRED` are out of scope for v0.1.
- Unexpected exceptions are logged internally and exposed as a generic FAILED Task message.
- Task history means A2A Message history, not state transition history.

The in-memory Task Store is intended for development and simple synchronous workloads. Tasks are not guaranteed to survive Rails process restarts or be shared across multiple processes.

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
- Task lifecycle, result mapping, Artifact mapping, and Task storage live under `A2A::Rails::Task`.
- The default v0.1 Task Store is in-memory.
- v0.1 generators are limited to `install` and `agent`.
- `install` creates only the initializer with a generic `"YourAgent"` placeholder.
- `agent` creates only the Agent scaffold; it does not reference a nonexistent Handler or register the Agent automatically.
- Registered Agent validation happens when A2A endpoints are used; incomplete A2A configuration does not fail host Rails boot.
- Rails integration tests use a minimal `test/dummy` application.
- ActiveRecord and ActiveJob are not required dependencies.
- v0.1 now targets Ruby `>= 3.3` and Rails `>= 8.0, < 8.2`; the SDK dependency graph cannot resolve on Ruby 3.2.
- The spike verified `agent2agent = 2.0.0`; the first implementation dependency is planned as `~> 2.0.0`. The Adapter must supply version / validation / Rack input handling and safe logging. Rails 8.0 also needs the documented JSON compatibility constraint.

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

