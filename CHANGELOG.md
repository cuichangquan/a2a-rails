# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — outbound Client v0.3.x proposal (NO-GO)

> **Not released, tagged or published.** This entry describes source changes merged
> **after** the published stable `0.2.0`. The gemspec/source `VERSION`
> still reads `0.2.0`, so it is **not** a versioned 0.3.x release
> candidate. See [Step 29-5p security readiness NO-GO](docs/release/v0.3.x-client-pre-release-security-review.md)
> and open [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90).

### Proposed added capabilities (on main, unreleased)

- Outbound Rails `A2A::Rails::Client` for strict HTTPS Agent Card
  discovery and A2A v1.0 JSON-RPC `SendMessage`, `GetTask`, `ListTasks`,
  `CancelTask`, with separate Card/RPC credential callbacks, immutable
  plain-Ruby results, direct Message or Task output and Client-only Rails mode.
- Explicit approved origin and public-IPv4 pinned socket policy, ordinary
  hostname/SNI/CA verification, zero automatic transport retries, bounded
  timeouts/request-response sizes and safe error categories. Host secrets,
  tenant authorization and recovery are **not** implemented automatically.
- Structural validation of Message, nested Task/Artifact and File/Data Parts.
  Native official Python and Go SDK local HTTPS interoperability, plus
  genuine Solid Queue/Sidekiq separately executing outbound Client workers
  on Rails 8.0/8.1, all tracked with scoped test limitations.

### Security and compatibility notes

- Source-hardening tests cover DNS/SSRF, TLS/auth/log privacy, gzip and
  malformed/chunked/truncated HTTP, JSON nesting, ambiguous remote
  SendMessage/CancelTask timeout and nested response validation.
- **Go SDK follow-up:** Step 29-5q verified authenticated Go ListTasks pagination with two scoped test users and isolated Task visibility; anonymous callers still receive `-31401`.
- **Open review items:** exact versioned v0.3.x candidate tests and
  candidate Gem SHA256, installed-host verification, an independent security
  reviewer, and final explicit publication/public-test scope decisions.
- Publishing a Gem and approving open-public **production deployment**
  are distinct; a host must provide credential issuer verification,
  business authorization, rate/concurrency and operational limits.
  No release approval is implied by any CI PASS.

## [0.2.0] - 2026-10-08 (published stable release)

> **Published in Step 27 after explicit approval.** [GitHub Release](https://github.com/cuichangquan/a2a-rails/releases/tag/v0.2.0) and [RubyGems 0.2.0](https://rubygems.org/gems/a2a-rails/versions/0.2.0) contain the exact verified artifact, with no rebuild. See the [publication record](docs/release/v0.2.0-publication-record.md) for its SHA256 and public-download verification. The immutable `0.2.0.rc2` pre-release **does not include the subsequent fixes** below.

### Added

- A2A v1.0 **Task and optional direct Message** responses; explicit output File Parts through `FileArtifact.bytes` and `.url`.
- **Opt-in ActiveRecordStore** with owner-scoped persistent Tasks, PostgreSQL locking, signed pagination cursors, generated migration, retention, bounded pruning, resource guards and maintenance statistics. **MemoryStore remains the default**.
- **Opt-in ActiveJob async Task execution** with global / Agent / Skill configuration; durable Store + operated durable queue required for reliable multi-process use. Default processing stays synchronous; direct Message execution stays synchronous.
- Host-owned HTTP Bearer authentication and corresponding Agent Card advertisement, fail-closed production endpoint behavior, principal-scoped Task operations, bounded request parsing and safer error handling. **The Gem does not implement the host's identity provider or business authorization.**
- Source-built **installed-artifact** Rails 8.0/8.1 + PostgreSQL 16 production-host checks, realistic signed-token **test fixture** for negative authentication/tenant isolation, and Solid Queue/Sidekiq worker SIGKILL and duplicate delivery smoke. See [Step 26 release gates](docs/release/v0.2.0-stable-readiness.md).

### Fixed

- **Issue #65:** configure the Rails/Zeitwerk `a2a` basename as `A2A` in the Engine without mutating global ActiveSupport inflections, preventing production eager-load errors in clean Rails 8.0/8.1 applications.
- Generate the ActiveRecord Task Store migration class from the host's ActiveSupport inflections, so both standard `CreateA2aRailsTasks` and host-configured acronym `CreateA2ARailsTasks` cases migrate without fixture patches.

### Changed / upgrade notes

- **Potential v0.1.0 breaking change:** non-development/test environments fail closed without a configured trusted `authenticate_request` hook and matching Bearer Agent Card metadata; tasks are isolated by authenticated principal. See [upgrade guide](docs/release/upgrading-v0.1.0-to-v0.2.md).
- Reject oversized/malformed/unsupported HTTP input earlier; only verified non-secret principal IDs may drive Task ownership.
- No general-purpose automatic Handler retries, forceful in-flight cancellation, or exactly-once external side effects. A Task committed just before enqueue can remain SUBMITTED; a crashed worker can leave an ambiguous WORKING Task. Business idempotency and reconciliation are **host responsibilities**.
- Ruby **>= 3.3**, Rails **>= 8.0, < 8.2**, A2A protocol **v1.0**, `agent2agent ~> 2.0.0`. No universal production certification; per-deployment security [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) remains open.

## [0.2.0.rc2] - 2026-10-08 (published pre-release; historical artifact)

> Published as the **rc2 pre-release** on RubyGems after separate approval in Step 25. Verified published artifact SHA256: `d65fdd65003987ece96f0a90a4cf28563929be99d26658deeb275fca30c5d694`. Later Step 26 fixes (including #65) are **not** in that immutable rc2 Gem.

### Added

- **Step 22-10 docs / release gates:** README, roadmap, ActiveJob design and release checklist now describe the implemented async configuration, durable Store + durable queue production requirements, enqueue crash window, retry/idempotency limits, best-effort cancellation, ambiguous WORKING recovery policy, and the fresh-candidate verification gates required before publication.

- **Step 22-9 HTTP async verification:** real Rails HTTP plus separate Solid Queue/Sidekiq workers cover SUBMITTED/WORKING/terminal state visibility, owner propagation/isolation, route-once, cancellation and Web/worker restart persistence. Shared smoke setup keeps adapter coverage consistent.

- **Step 22-8 queue-adapter verification:** isolated Solid Queue and Sidekiq smoke tests use real queues and separate workers on Rails 8.0 / 8.1, covering minimal payloads, terminal outcomes, duplicate/canceled delivery and queued work after worker restart. Backend Gems remain smoke-only dependencies.

- **Step 22-7 duplicate/idempotency verification:** serialized duplicate delivery during WORKING cannot start another Handler or finalize its Task. Added terminal-claim contracts and PostgreSQL cross-process claim contention coverage; documented Task-key scope and host business idempotency.

- **Step 22 cancellation semantics:** canceling a queued SUBMITTED Task prevents later execution claim; canceling a WORKING Task is logical/best-effort and terminal-state immutability prevents late Handler completion from replacing CANCELED. No queue-backend-specific force-kill API is used.
- **Step 22 enqueue/retry semantics:** ActiveJob enqueue success is checked explicitly, enqueue failure becomes a sanitized FAILED Task, the Gem-owned Task job enqueues immediately rather than deferring to a surrounding Active Record transaction, and Handler exceptions are converted to terminal Task state without generic automatic retry.
- **Step 22 ActiveJob execution core:** synchronous Task execution remains the default; hosts can opt into async execution globally, per Agent, or per Skill with `Skill > Agent > global` precedence. Async `SendMessage` now persists and returns `SUBMITTED`, enqueues a Gem-owned `ActiveJob` job, reloads the original Message from the Task Store, executes the already-selected Skill, and transitions to a terminal Task state. MemoryStore and ActiveRecordStore provide an atomic `SUBMITTED -> WORKING` execution claim to suppress duplicate starts.
- **Step 21 ActiveRecord Task Store core:** optional lazy-loaded ActiveRecord backend, owner-scoped SQL lookups, row-locked transitions/cancellation, signed keyset pagination, migration generator, and durable restart/multi-instance semantics.
- **Step 21 lifecycle maintenance:** 30-day terminal retention by default for ActiveRecordStore, bounded batch pruning, aggregate maintenance stats, per-owner retained-Task admission guard, and persisted history/artifact collection limits.

## [0.2.0.rc1] - 2026-10-07 (release candidate source; not published)

> **Not published on RubyGems.** The released v0.1.0 artifact does not contain these changes. The candidate source now uses `A2A::Rails::VERSION = "0.2.0.rc1"` for exact artifact verification; no tag/Release/RubyGems publication is authorized yet. Distribution readiness and public-production readiness remain separate decisions.

### Added

- **Step 20 RC verification:** Candidate version `0.2.0.rc1`, exact-artifact CI for one built `.gem` reused across Rails 8.0/8.1 installed-artifact security smoke, release/upgrade guidance, and separated publication vs deployment gates. No tag/RubyGems publication.

- **Unreleased Step 19 (docs / separate repository):** [a2a-rails-demo](https://github.com/cuichangquan/a2a-rails-demo), a standalone Rails 8.1 Echo Agent app with pinned unreleased Gem source, Task/direct Message Quick Start and real localhost HTTP smoke (16 checks passed). No changes to Gem runtime or published RubyGems v0.1.0.

- **Unreleased Step 18:** Standalone CI smoke tests using independent official Python SDK 1.2.2 and Go SDK v2.6.0 against a loopback Rails JSON-RPC A2A v1.0 Agent. Verified both Task and direct Message responses and Task operations; no Gem runtime behavior changed. See [cross-language interoperability evidence](docs/testing/cross-language-interop.md).

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
