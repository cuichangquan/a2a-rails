# a2a-rails

Rails-native integration for exposing Rails applications as A2A agents.

> **Status: Design phase — implementation has not started yet.**

## Current Status

The project is currently defining the v0.1 architecture and public API before implementation.

**Current stage:** Step 9 completed — Public API Design

**Next step:** **Step 10 — Agent Card Design**

The next design work will decide:

- Agent DSL to Agent Card field mapping
- `/.well-known/agent-card.json` response structure
- public endpoint URL generation
- Skill mapping
- v0.1 capabilities
- protocol / transport metadata

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
- [ ] **10. Agent Card Design ← NEXT**
- [ ] 11. Task Lifecycle Design
- [ ] 12. Test Strategy
- [ ] 13. Gem Structure
- [ ] 14. Quick Start Design
- [ ] 15. Start Implementation

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

- [v0.1 Design Decisions](docs/design/v0.1-decisions.md) — current architecture, scope, terminology, SDK boundary, public API, and design principles.

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
end
```

v0.1 targets **one public A2A Agent per Rails application**, with multiple Skills handled by Rails-side Handlers.
