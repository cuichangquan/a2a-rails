# a2a-rails

Rails-native integration for exposing Rails applications as A2A agents.

> **Status: the generator-backed Echo Quick Start is implemented and runtime-verified from source; packaged-gem release readiness is next.**

## Current Status

The A2A v1.0 SDK integration path, Gem core, Protocol Adapter, Agent / Skill DSL, Task lifecycle, Configuration, Agent Card generation, Rails Engine HTTP endpoints, and the `install` / `agent` generators are now runtime-verified.

**Current stage:** Step 15-11 completed — generators + generated Echo Quick Start

**Next step:** **Step 15-12 — Verify the built `.gem` in a clean Rails application and complete v0.1 release readiness.**

Step 15-11 adds the two intentionally small generators:

```bash
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent echo
```

The integration smoke invokes those generator namespaces, verifies their exact output, applies the documented Echo Handler / Skill setup, boots a minimal Rails application, retrieves the Agent Card, and sends a real A2A `SendMessage` request through `/a2a`. The response reaches `TASK_STATE_COMPLETED` with an `Echo: Hello` Artifact. The supported CI matrix is **12 / 12 green**, and the Gem suite runs **70 tests / 240 assertions / 0 failures / 0 errors / 0 skips**. See [Draft PR #5](https://github.com/cuichangquan/a2a-rails/pull/5).

Step 15-10 implemented the automatically mounted Rails Engine, thin API controllers, a process-local Runtime that shares the in-memory Task Store across HTTP requests, and the Rails-facing SDK logging boundary. Step 15-9 implemented lazy Configuration and Agent Card generation. Step 15-8 wired `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` through the real SDK. Step 15-7 implemented the SDK-independent Task core. Step 15-6 implemented the Rails-facing Agent / Skill / Dispatcher API. Step 15-5 introduced the loadable Gem skeleton and Protocol Adapter. Step 15-4 verified the `agent2agent 2.0.0` SDK path across the supported Ruby / Rails matrix.

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
- [ ] **15. Implementation / release preparation ← IN PROGRESS**
  - [x] 15-4 SDK compatibility spike
  - [x] 15-5 Gem skeleton + Protocol Adapter
  - [x] 15-6 Agent / Skill DSL + Dispatcher
  - [x] 15-7 Task core + MemoryStore
  - [x] 15-8 Task operations through real SDK
  - [x] 15-9 Configuration + Agent Card
  - [x] 15-10 Rails Engine HTTP integration
  - [x] 15-11 Generators + generated Quick Start
  - [ ] 15-12 Packaged-gem / release-readiness verification

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

## Quick Start

> The flow below is runtime-verified from the repository source tree in Step 15-11. The project has not yet completed packaged-gem / release verification.

### 1. Add and install

```bash
bundle add a2a-rails
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent echo
mkdir -p app/services/echo
```

`install` creates only:

```text
config/initializers/a2a_rails.rb
```

with:

```ruby
A2A::Rails.configure do |config|
  config.agent = "YourAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

`agent echo` creates only:

```text
app/agents/echo_agent.rb
```

with:

```ruby
class EchoAgent < A2A::Rails::Agent
  name "Echo Agent"
  description "TODO"
  version "1.0"

  # Add at least one skill.
end
```

The generator deliberately does **not** create a Handler, route, controller, Task Store, job, migration, or registration side effect. It also does not reference a Handler that does not exist yet.

### 2. Create the Handler

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

### 3. Define the Skill

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

A single Skill is selected automatically. No Router is required.

### 4. Register the Agent

Replace `config/initializers/a2a_rails.rb` with:

```ruby
A2A::Rails.configure do |config|
  config.agent = "EchoAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

For localhost, leave `A2A_PUBLIC_BASE_URL` unset or set it to `http://localhost:3000`. The Agent class name remains a String until an A2A endpoint resolves it, preserving Rails autoload / reload behavior.

No explicit Engine mount or host `config/routes.rb` change is required.

### 5. Check the Agent Card

```bash
bin/rails server
```

```bash
curl -sS http://localhost:3000/.well-known/agent-card.json \
  -H "A2A-Version: 1.0"
```

Expected essentials:

- HTTP 200
- Agent name `Echo Agent`
- Skill ID `reply`
- JSON-RPC A2A interface pointing to `http://localhost:3000/a2a`

### 6. Send the first message

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

Success means:

```text
result.task.status.state == TASK_STATE_COMPLETED
Artifact Text Part == "Echo: Hello"
```

See [the complete Quick Start design and verification notes](docs/design/quick-start.md).

## Target Developer Experience

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

v0.1 targets **one public A2A Agent per Rails application**. Handlers receive SDK-independent Ruby Hashes for `message` and `context`.

For multiple Skills, the application supplies a Router. The Router receives `skills:` as a frozen `Array<Symbol>` of declared Skill IDs and may return a matching Symbol or String. Unknown selections raise `A2A::Rails::UnknownSkillError`; the Dispatcher never silently chooses the first Skill.

## Agent Card

The Gem automatically exposes:

```text
GET  /.well-known/agent-card.json
POST /a2a
```

Agent Card behavior:

- generated from the Agent / Skill DSL;
- Skill IDs and default display names are generated from Skill declarations;
- optional `examples`, `input_modes`, and `output_modes` map to A2A Agent Card fields;
- Handler internals are never exposed;
- `public_base_url` wins when configured, otherwise the request base URL is used;
- default input/output mode is `text/plain`;
- Streaming, Push Notifications, and Extended Agent Cards are disabled for v0.1;
- generated Cards pass the real `agent2agent 2.0.0` Agent Card schema.

## Task Lifecycle

Internally the Gem keeps SDK-independent Task states:

```text
SUBMITTED
    ↓
WORKING
    ├──→ COMPLETED
    ├──→ FAILED
    └──→ REJECTED
```

Cancellation can move a non-terminal Task to `CANCELED`.

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
other object → ArtifactMappingError
```

v0.1 Task behavior:

- server-generated Task IDs;
- client Context ID preserved, otherwise server-generated;
- terminal states are immutable;
- thread-safe process-local `Task::MemoryStore` by default;
- `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` supported;
- `ListTasks` supports context/state/timestamp filters, stable newest-first ordering, page sizes 1–100, and opaque snapshot pagination;
- cancellation is atomic, but does not interrupt Handler execution or undo business side effects;
- v0.1 Handler execution accepts text Message Parts;
- continuing an existing Task via `message.taskId` is not supported;
- `INPUT_REQUIRED` and `AUTH_REQUIRED` are out of scope.

The default store is for development and simple synchronous workloads. Tasks and pagination cursors are process-local and are not durable across process restarts or shared between processes.

## Rails Integration

Step 15-10 provides:

- an automatically mounted Rails Engine;
- thin `ActionController::API` controllers;
- `/.well-known/agent-card.json` and `/a2a` routes;
- lazy application Agent resolution;
- one process-local Runtime that shares the default Task Store across HTTP requests;
- request-derived Agent Card URL fallback;
- a logging boundary that suppresses the upstream SDK `A2A::Server::Triage` INFO log containing the full Rack environment while restoring prior Console logging state afterward.

## Generators

Step 15-11 implements:

```text
a2a:rails:install
a2a:rails:agent NAME
```

Verified contract:

- `install` creates only `config/initializers/a2a_rails.rb`;
- `agent echo` creates only `app/agents/echo_agent.rb`;
- the Agent scaffold has no dangling Handler reference;
- the generated Agent is not automatically registered;
- namespace-based generator invocation reproduces the documented files;
- the generated Echo setup boots under Rails and completes a real A2A `SendMessage` request.

The remaining release-readiness gap is verifying these generators after building/installing the `.gem`, using a clean Rails application rather than the repository source checkout.

## Test Strategy

v0.1 uses **Minitest** with four layers:

```text
4. Protocol E2E / Smoke Tests
3. Rails Integration Tests
2. Adapter Contract Tests
1. Core Unit Tests
```

The current CI matrix covers:

- Gem: Ruby 3.3 / 3.4 / 4.0
- SDK spike: Ruby 3.3 / 3.4 / 4.0
- Rails: Ruby 3.3 / 3.4 / 4.0 × Rails 8.0 / 8.1

Current Step 15-11 result:

```text
12 / 12 CI jobs green
70 tests
240 assertions
0 failures
0 errors
0 skips
```

Known warning-enabled output from upstream `agent2agent 2.0.0` remains, including circular-require / indentation / URI-parser warnings. Those warnings are distinct from the Rack-environment INFO logging that a2a-rails suppresses at the Rails-facing adapter boundary.

## Gem Structure

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

lib/generators/a2a/rails/
├── install_generator.rb
├── agent_generator.rb
└── templates/
```

Key boundaries:

- Rails Engine / controllers / routes are only the Rails integration layer.
- SDK-specific behavior stays behind `Protocol::Adapter` / `Protocol::Agent2AgentAdapter`.
- A2A camelCase fields, `TASK_STATE_*`, SDK schema objects, and SDK errors stay in the Protocol layer.
- Agent / Handler application constants remain lazily resolved through Rails.
- ActiveRecord and ActiveJob are not runtime requirements.
- v0.1 targets Ruby `>= 3.3` and Rails `>= 8.0, < 8.2`.

Current main dependencies:

- `agent2agent ~> 2.0.0`
- `actionpack >= 8.0, < 8.2`
- `json < 3`
- `rack >= 3.0, < 4`
- `railties >= 8.0, < 8.2`

## v0.1 Scope

Included:

- Rails integration
- `A2A::Rails::Agent`
- Skill DSL and Handler dispatch
- Agent Card generation
- `/.well-known/agent-card.json`
- `POST /a2a`
- Task lifecycle
- `GetTask`, `ListTasks`, `CancelTask`
- `A2A-Version: 1.0` validation
- in-memory Task Store
- Rails Engine / Routes
- Configuration
- `install` / `agent` generators
- Rails logging boundary
- test support

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

## Design Documents

- [v0.1 Design Decisions](docs/design/v0.1-decisions.md)
- [v0.1 Test Strategy](docs/design/test-strategy.md)
- [v0.1 Gem Structure](docs/design/gem-structure.md)
- [v0.1 Quick Start Design](docs/design/quick-start.md)
- [Step 15 SDK compatibility findings](docs/design/sdk-compatibility-spike.md)
