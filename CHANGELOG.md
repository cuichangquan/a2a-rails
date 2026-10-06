# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-06

### Added

- Rails-native A2A v1.0 server integration backed by `agent2agent ~> 2.0.0`.
- `A2A::Rails::Agent` and Skill DSL with application-owned Handler dispatch.
- Single-Skill automatic dispatch and multi-Skill Router support.
- Agent Card generation at `GET /.well-known/agent-card.json`.
- A2A JSON-RPC endpoint at `POST /a2a`.
- Synchronous Task lifecycle with `SUBMITTED`, `WORKING`, `COMPLETED`, `FAILED`, `REJECTED`, and `CANCELED` states.
- String, Hash, Array, and nil Handler-result mapping to A2A Artifacts.
- Thread-safe process-local in-memory Task Store.
- `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` support.
- `ListTasks` filtering, stable newest-first ordering, and opaque snapshot pagination.
- Lazy Rails configuration and Agent resolution.
- Automatically mounted Rails Engine and thin API controllers.
- Rails-facing logging boundary that suppresses the upstream SDK Rack-environment INFO log.
- `a2a:rails:install` and `a2a:rails:agent NAME` generators.
- Generator-backed Echo Quick Start verified through a real packaged `.gem` installed into a clean Rails application.
- CI coverage for Ruby 3.3, 3.4, and 4.0 with Rails 8.0 and 8.1.

### Compatibility

- Ruby `>= 3.3`.
- Rails `>= 8.0, < 8.2`.
- A2A protocol version `1.0`.
- `agent2agent ~> 2.0.0`.

### Known limitations

- Server-only; no A2A client.
- Non-streaming synchronous execution only.
- No Push Notifications, gRPC, ActiveJob execution, or durable Task Store.
- Default Task Store is process-local and is not shared across processes or preserved across restarts.
- Handler cancellation does not interrupt already-running application code or undo business side effects.
- `INPUT_REQUIRED` and `AUTH_REQUIRED` flows are not implemented.
- Continuing an existing Task via `message.taskId` is not supported in v0.1.
