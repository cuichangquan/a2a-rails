# a2a-rails v0.1 Gem Structure

This document records the Step 13 decisions for the physical structure of the `a2a-rails` gem.

The main rule is:

> Keep Rails integration thin, keep core behavior under `lib/a2a/rails`, and isolate Ruby A2A SDK-specific code behind an internal Protocol Adapter.

---

## 1. Top-level structure

```text
a2a-rails/
├── lib/
│   ├── a2a-rails.rb
│   ├── a2a/
│   │   └── rails/
│   │       ├── version.rb
│   │       ├── engine.rb
│   │       ├── configuration.rb
│   │       ├── agent.rb
│   │       ├── skill.rb
│   │       ├── dispatcher.rb
│   │       ├── errors.rb
│   │       ├── agent_card/
│   │       ├── task/
│   │       └── protocol/
│   └── generators/
│       └── a2a/
│           └── rails/
├── app/
│   └── controllers/
│       └── a2a/
│           └── rails/
├── config/
│   └── routes.rb
├── test/
│   ├── test_helper.rb
│   ├── unit/
│   ├── protocol/
│   ├── contract/
│   ├── integration/
│   ├── e2e/
│   └── dummy/
├── docs/
├── Gemfile
├── Rakefile
├── a2a-rails.gemspec
├── LICENSE
└── README.md
```

Gem behavior belongs primarily under `lib/a2a/rails/`. `app/`, `config/`, and `engine.rb` contain only the Rails-specific integration layer needed to expose the gem inside a Rails application.

---

## 2. Internal namespace layout

```text
lib/a2a/rails/
├── version.rb
├── engine.rb
├── configuration.rb
├── agent.rb
├── skill.rb
├── dispatcher.rb
├── errors.rb
├── agent_card/
│   ├── builder.rb
│   └── validator.rb
├── task/
│   ├── lifecycle.rb
│   ├── result_mapper.rb
│   ├── artifact_mapper.rb
│   ├── store.rb
│   └── memory_store.rb
└── protocol/
    ├── adapter.rb
    └── agent2agent_adapter.rb
```

Responsibilities:

- `Agent` — Rails-facing Agent DSL.
- `Skill` — immutable-ish Skill definition and metadata.
- `Dispatcher` — resolves a Skill and invokes its Handler.
- `AgentCard::Builder` — builds Agent Card data from the registered Agent definition.
- `AgentCard::Validator` — prevents invalid or partial Agent Cards from being exposed.
- `Task::Lifecycle` — owns Task creation and state transitions.
- `Task::ResultMapper` — maps Handler outcomes to Task outcomes.
- `Task::ArtifactMapper` — maps Handler return values to A2A Artifact data.
- `Task::Store` — minimal internal Task Store contract.
- `Task::MemoryStore` — v0.1 in-memory implementation.
- `Protocol::Adapter` — internal adapter contract.
- `Protocol::Agent2AgentAdapter` — SDK-specific integration for the current `agent2agent` candidate.

The Step 13 concrete namespace refines earlier conceptual names such as `TaskLifecycle` / `TaskStore` into `Task::Lifecycle` / `Task::Store`.

---

## 3. Dependency direction

```text
Rails HTTP Layer
      ↓
Protocol Adapter
      ↓
Dispatcher
      ↓
Skill
      ↓
Handler
      ↓
Rails Business Logic
```

Task lifecycle, Artifact mapping, and Task storage are internal components used by the execution path.

Rules:

- Controllers must remain thin.
- Handler code must not depend on the Ruby A2A SDK.
- Dispatcher must not know whether the request arrived through JSON-RPC or another future protocol implementation.
- SDK-specific request objects, errors, and serialization types must not leak into the Rails-facing Public API.

---

## 4. Rails Engine and HTTP layer

```text
lib/a2a/rails/engine.rb

app/controllers/a2a/rails/
├── agent_cards_controller.rb
└── requests_controller.rb

config/routes.rb
```

v0.1 standard endpoints:

```text
GET  /.well-known/agent-card.json
POST /a2a
```

Controller responsibilities:

```text
AgentCardsController
    → invoke AgentCard::Builder
    → render Agent Card JSON

RequestsController
    → pass the incoming request to the Protocol Adapter
    → render the protocol response
```

Controllers do not perform Skill lookup, Handler execution, Task state transitions, Artifact conversion, or SDK-specific protocol processing.

The target developer experience is that adding the gem enables the standard routes without requiring an explicit Engine mount in the host application's `routes.rb`.

---

## 5. Protocol Adapter

```text
lib/a2a/rails/protocol/
├── adapter.rb
└── agent2agent_adapter.rb
```

The adapter boundary separates the protocol / SDK world from the gem's internal Rails-oriented world.

Conceptual interface:

```ruby
module A2A
  module Rails
    module Protocol
      class Adapter
        def handle(request:)
          raise NotImplementedError
        end
      end
    end
  end
end
```

`Protocol::Agent2AgentAdapter` is responsible for:

- interpreting an A2A request through the Ruby SDK,
- converting SDK objects into a2a-rails internal values,
- invoking the Dispatcher / Task execution path,
- converting the result back into the SDK response shape,
- absorbing SDK-specific errors at the boundary.

It must not contain Rails business logic or directly own Task persistence.

v0.1 does not expose an adapter selection API such as:

```ruby
config.protocol_adapter = :agent2agent
```

The boundary exists so a future Official Ruby SDK can replace the implementation without redesigning the public Agent / Skill / Handler API.

---

## 6. Task components

```text
lib/a2a/rails/task/
├── lifecycle.rb
├── result_mapper.rb
├── artifact_mapper.rb
├── store.rb
└── memory_store.rb
```

### Lifecycle

Owns the supported v0.1 transitions:

```text
SUBMITTED
    ↓
WORKING
    ├──→ COMPLETED
    ├──→ FAILED
    └──→ REJECTED
```

### Result Mapper

Maps execution outcomes:

```text
normal Handler return          → COMPLETED
A2A::Rails::RejectedTask       → REJECTED
unexpected exception           → FAILED
```

### Artifact Mapper

Maps successful Handler return values:

```text
String       → Text Part
Hash / Array → Data Part
nil          → no Artifact
```

### Store

The v0.1 store contract remains minimal. It only needs the operations required by Task execution and `GetTask`; list, filter, pagination, and cancellation APIs are not introduced.

### Memory Store

`Task::MemoryStore` is the v0.1 default implementation.

It does not guarantee persistence across Rails restarts or sharing across multiple Rails processes. ActiveRecord and Redis stores are future extensions, not v0.1 dependencies.

---

## 7. Generators

```text
lib/generators/a2a/rails/
├── install_generator.rb
├── agent_generator.rb
└── templates/
    ├── initializer.rb
    └── agent.rb
```

v0.1 generators:

```text
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent shopping
```

`install` creates the initializer.

`agent` creates an application-owned Agent under:

```text
app/agents/shopping_agent.rb
```

v0.1 intentionally does not add generators for Handlers, Task Stores, controllers, protocol adapters, database migrations, or ActiveJob execution.

Handler placement remains an application decision.

---

## 8. Test and dummy application structure

```text
test/
├── test_helper.rb
├── unit/
│   ├── agent_test.rb
│   ├── skill_test.rb
│   ├── dispatcher_test.rb
│   ├── configuration_test.rb
│   ├── agent_card/
│   └── task/
├── protocol/
│   └── agent2agent_adapter_test.rb
├── contract/
│   └── agent2agent_adapter_contract_test.rb
├── integration/
│   ├── agent_card_test.rb
│   └── a2a_request_test.rb
├── e2e/
│   └── critical_flow_test.rb
└── dummy/
    ├── app/
    │   ├── agents/
    │   └── services/
    └── config/
```

Meaning:

- `unit/` — core gem behavior.
- `protocol/` — Protocol Adapter unit tests with the Ruby A2A SDK mocked; conceptually part of the unit-test layer defined by the Test Strategy.
- `contract/` — real Ruby A2A SDK boundary tests.
- `integration/` — Rails Engine / routes / controllers / configuration through the dummy application.
- `e2e/` — Critical E2E scenarios with gem-internal components unmocked.
- `dummy/` — a minimal integration fixture, not a showcase application.

The dummy app should avoid UI, unnecessary models, database requirements, Devise, ActiveJob, and other unrelated framework features.

---

## 9. Runtime dependencies and supported versions

v0.1 targets:

```text
Ruby  >= 3.2
Rails >= 8.0, < 8.2
```

The gem should depend on the Rails components it actually needs rather than the full `rails` meta-gem:

```ruby
spec.required_ruby_version = ">= 3.2"

spec.add_dependency "railties", ">= 8.0", "< 8.2"
spec.add_dependency "actionpack", ">= 8.0", "< 8.2"
```

v0.1 must not require:

```text
activerecord
activejob
actioncable
```

`agent2agent` remains the first Ruby A2A SDK candidate. Its exact version constraint should be pinned only after the implementation compatibility spike verifies the supported Ruby / Rails matrix.

Do not leave the final SDK dependency unconstrained.

---

## 10. CI compatibility matrix

The intended release matrix is:

```text
Ruby 3.2 ─┬─ Rails 8.0
          └─ Rails 8.1

Ruby 3.3 ─┬─ Rails 8.0
          └─ Rails 8.1

Ruby 3.4 ─┬─ Rails 8.0
          └─ Rails 8.1

Ruby 4.0 ─┬─ Rails 8.0
          └─ Rails 8.1
```

All supported combinations must pass the release test suite before a release is published.

---

## 11. Final Step 13 decisions

```text
Gem core                → lib/a2a/rails
Rails HTTP integration  → Engine + app/controllers + config/routes.rb
Protocol SDK isolation  → Protocol::Adapter / Agent2AgentAdapter
Task implementation     → A2A::Rails::Task namespace
Default Task Store      → MemoryStore
Generators              → install + agent only
Rails integration test  → test/dummy
Test framework          → Minitest
Ruby support            → >= 3.2
Rails support           → >= 8.0, < 8.2
ActiveRecord required   → no
ActiveJob required      → no
```

The structure is intentionally small enough for v0.1 while preserving clean boundaries for future SDK replacement, persistent Task Stores, asynchronous execution, and additional protocol capabilities.

---

## 12. Next Step

**Step 14: Quick Start Design**

Step 14 should define the exact first-time developer path from adding the gem to successfully serving an Agent Card and handling the first A2A request.