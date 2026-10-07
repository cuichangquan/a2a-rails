# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Security hardening (Steps 16-1–16-6)

> **Not published on RubyGems.** The released v0.1.0 artifact does not contain these changes. A release version, compatibility decision and full deployment security assessment are still pending.

### Added

- **Unreleased Step 17-4:** Explicit Agent-level `response_mode :message` or a host-controlled callable to return a direct A2A v1.0 Message from `SendMessage` without Task persistence; default remains `:task`. Reuses outbound String/Hash/Array/FileArtifact part mapping, adds SDK integration tests, and exercises the pinned TCK direct-Message fixture. No published gem has these features yet.

- **Unreleased Step 17-3:** Explicit `A2A::Rails::FileArtifact.bytes(data:, filename:, media_type:)` and `.url(url:, filename:, media_type:)` Handler output for A2A v1.0 file `raw`/HTTPS `url` Parts. Raw bytes are Base64-encoded, metadata validated, and existing String/Hash/Array/nil returns remain unchanged. Local official TCK and SDK integration coverage track progress.

- Host-owned `config.authenticate_request` and explicit Agent Card Bearer security declaration (`security_schemes` / `security_requirements`).
- Owner-scoped Task retrieval, listing, cancellation and pagination, with host-verified opaque principal IDs.
- Input body limit (`max_request_bytes`, default 1 MiB), defensive message/query type checks and HTTP boundary errors.
- Bounded in-process pagination snapshot count and reduced exception-detail logging.
- Threat model, authentication/request-hardening guides, production deployment review and release acceptance checklist.
- Negative security tests, real Rails HTTP authentication tests and production-environment fail-closed smoke tests.

### Changed — potentially incompatible with v0.1.0

- In production and staging, unconfigured A2A authentication now fails closed (`POST /a2a` 401); missing/inconsistent Agent Card security configuration does not publish an unauthenticated card.
- Host verifiers must have matching Agent Card Bearer metadata.
- Task operations are restricted to each authenticated principal; anonymous local-only Tasks are separate.
- Invalid Content-Type, oversized requests and malformed fields are rejected before Task dispatch.

### Deployment limitations

- **NO-GO for open public production using the default MemoryStore:** Tasks are not durable, have no TTL/total-count cap and are isolated per worker; the Gem does not implement distributed rate limiting or timeouts for arbitrary Handler code.
- Host applications must enforce token verification, tenant-qualified identities, business-action authorization, HTTPS and ingress/compute quotas. Cancellation does not interrupt running Handlers.
- Release version and artifact publication require separate approval and verification.

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
