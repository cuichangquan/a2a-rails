# a2a-rails

Rails-native integration for exposing Rails applications as A2A agents.

> **Status: Design phase — implementation has not started yet.**

## Current Status

The project is currently defining the v0.1 architecture and public API before implementation.

**Current stage:** Step 8 completed — Ruby A2A SDK boundary design

**Next step:** **Step 9 — Public API Design**

The next design work will decide:

- Agent DSL
- Skill DSL
- Handler interface
- Agent registration
- Routing
- Configuration API
- Error handling API

## Development Progress

- [x] 1. Research A2A Protocol v1.0
- [x] 2. Research Ruby A2A SDKs / Gems
- [x] 3. Research Rails-oriented A2A alternatives
- [x] 4. Define the problem a2a-rails solves
- [x] 5. Define v0.1 scope
- [x] 6. Define terminology
- [x] 7. Define architecture
- [x] 8. Define Ruby SDK boundary
- [ ] **9. Public API Design ← NEXT**
- [ ] 10. Agent Card Design
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

- [v0.1 Design Decisions](docs/design/v0.1-decisions.md) — current architecture, scope, terminology, SDK boundary, and design principles.

## Target Developer Experience

The intended Rails-facing API is approximately:

```ruby
class ShoppingAgent < A2A::Rails::Agent
  name "Shopping Agent"
  description "Search and purchase products"

  skill :search_products,
    handler: Shopping::SearchProducts
end
```

The exact public API is **not finalized yet**. It will be decided in Step 9 before implementation begins.
