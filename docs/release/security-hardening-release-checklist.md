# Security hardening — release and deployment readiness checklist

Last reviewed: **2026-10-07 (Step 22)**  
Baseline published release: **a2a-rails 0.1.0** (2026-10-06)  
Current main: includes Steps 16–22, including optional durable ActiveRecord Task Store and opt-in ActiveJob Task execution.  
Release-candidate status: **`0.2.0.rc2` is selected for fresh verification; no candidate is approved for publication**.

> The historical `0.2.0.rc1` artifact verified in Step 20 predates Step 21 and Step 22 runtime changes. Its commit/SHA evidence remains valid for that exact historical tree only and **must not be reused**. Step 23 selects `0.2.0.rc2` for a fresh exact-candidate verification.

## Decision

Release and deployment decisions remain separate.

| Decision | Status |
| --- | --- |
| Prepare a **new** candidate from current main | **GO for `0.2.0.rc2` verification only** |
| Tag / GitHub Release / RubyGems publication | **NO-GO until new candidate gates pass + explicit approval** |
| Open public production using default MemoryStore | **NO-GO** |
| Multi-worker/restart-safe Task persistence using ActiveRecordStore | **Gem capability verified; deployment-specific GO/NO-GO still required** |
| Open public production overall | **NO-GO by default** until all host/deployment gates below are satisfied |

A durable Task Store removes one framework-level blocker. It does not provide credential verification, business authorization, distributed rate limiting, TLS policy, execution budgets or deployment monitoring.

## Evidence merged on main

- [x] [#12 — Step 16-1 threat model](https://github.com/cuichangquan/a2a-rails/pull/12)
- [x] [#13 — Step 16-2 authentication gate](https://github.com/cuichangquan/a2a-rails/pull/13)
- [x] [#15 — Step 16-3 principal ownership and cursor scoping](https://github.com/cuichangquan/a2a-rails/pull/15)
- [x] [#16 — Step 16-4 input limits, log hygiene and cursor cap](https://github.com/cuichangquan/a2a-rails/pull/16)
- [x] [#17 — Step 16-5 Bearer Agent Card security advertisement](https://github.com/cuichangquan/a2a-rails/pull/17)
- [x] [#18 — Step 16-6 production-mode fail-closed smoke / deployment review](https://github.com/cuichangquan/a2a-rails/pull/18)
- [x] Pinned official A2A TCK: **63 passed / 1 failed / 171 skipped / 30 deselected**; remaining CORE-SEND-003 mismatch is tracked upstream in [a2a-tck #202](https://github.com/a2aproject/a2a-tck/issues/202).
- [x] Official Python SDK 1.2.2 + Go SDK v2.6.0 interoperability: [Step 18](../testing/cross-language-interop.md).
- [x] Independent Rails 8 localhost demo: [a2a-rails-demo](https://github.com/cuichangquan/a2a-rails-demo), real HTTP smoke **16/16 PASS**.
- [x] Step 21 durable Store design: [PR #36](https://github.com/cuichangquan/a2a-rails/pull/36).
- [x] Step 21 ActiveRecordStore core: [PR #37](https://github.com/cuichangquan/a2a-rails/pull/37).
- [x] Step 21 retention/pruning/quota/payload maintenance: [PR #38](https://github.com/cuichangquan/a2a-rails/pull/38).
- [x] Shared MemoryStore/ActiveRecordStore contract + PostgreSQL 16 durability/locking smoke: [PR #39](https://github.com/cuichangquan/a2a-rails/pull/39), [PostgreSQL run #37595993690](https://github.com/cuichangquan/a2a-rails/actions/runs/37595993690) **PASS**.
- [x] Step 22 ActiveJob execution design/configuration/core/hardening: PRs #42–#48.
- [x] Step 22 real Solid Queue / Sidekiq separate-worker compatibility on Rails 8.0 / 8.1: [PR #50](https://github.com/cuichangquan/a2a-rails/pull/50), [queue adapter evidence](../testing/queue-adapters.md).
- [x] Step 22 real Rails HTTP async E2E: [PR #51](https://github.com/cuichangquan/a2a-rails/pull/51), including SUBMITTED/WORKING/terminal visibility, owner isolation, route-once, cancellation and graceful restart persistence.

## A. Current-main compatibility and release preparation

- [x] Production authentication and owner-scoped Task behavior are documented as potentially incompatible with published v0.1.0.
- [x] ActiveRecordStore is optional; MemoryStore remains default; ActiveRecord is not a runtime dependency for users who do not select it.
- [x] Durable Store migration, retention, pruning and operational limits are documented in [ActiveRecord Task Store](../guides/active-record-task-store.md).
- [x] SQLite unit/integration coverage and PostgreSQL 16 persistence/locking smoke are present.
- [x] ActiveJob execution is opt-in; synchronous Task execution remains the default; direct Message responses remain synchronous.
- [x] Async production requirements and limits are documented: durable Store + durable queue, enqueue crash window, no generic Handler retry, Task-level duplicate suppression, host business idempotency, best-effort cancellation and explicit reconciliation of ambiguous WORKING Tasks.
- [x] Update the v0.1.0 → next-v0.2 upgrade guide with Step 21 ActiveRecordStore configuration, migration and maintenance guidance.
- [x] Decide the **new candidate version** for current main: `0.2.0.rc2`. Do not reuse the historical rc1 artifact identity.
- [ ] On the exact new candidate tree, rerun Ruby/Rails CI, PostgreSQL Store CI, queue adapter + HTTP async E2E, production security smoke, Python/Go interoperability and the pinned official TCK (distinguishing the known upstream CORE-SEND-003 fixture issue).
- [ ] Build one exact `.gem`, inspect it, clean-install it into Rails 8.0 and 8.1, rerun installed-artifact security/runtime smoke, and record SHA256.
- [x] Update CHANGELOG/README/release preparation notes for the selected `0.2.0.rc2` candidate while preserving rc1 as historical-only evidence.

## B. Public-production deployment gates

These are deployment-specific gates. Passing Gem CI does not satisfy them automatically.

- [x] Gem-level tests cover authentication failure behavior and cross-principal Task read/list/cancel/pagination isolation.
- [x] Gem provides an optional owner-aware durable ActiveRecordStore with retention, bounded pruning, admission guard and persisted collection limits.
- [x] PostgreSQL 16 smoke proves cross-Store/fork-reconnect persistence and concurrent terminal-transition row locking.
- [ ] The actual deployment explicitly selects `config.task_store = :active_record` (or another reviewed durable Store), runs the migration, schedules pruning and verifies retention/quota settings.
- [ ] If async Task execution is enabled, configure and operate a durable ActiveJob backend; verify queue retention/restart behavior and deployment-specific queue topology.
- [ ] Define an operator procedure for the Task-commit/enqueue crash window and ambiguous `WORKING` Tasks. Do not blindly replay uncertain side effects.
- [ ] For side-effecting Handlers, enforce business-level idempotency keyed by `task_id` / `idempotency_key` (or an equivalent stronger domain key).
- [ ] Validate the **real host verifier** against expired, forged, revoked, wrong-issuer, wrong-audience and cross-tenant credentials.
- [ ] Verify application business-action authorization inside Handlers/services.
- [ ] Verify HTTPS ingress, trusted proxy / forwarded-header policy, host allowlisting, certificate trust and public Agent Card URL.
- [ ] Configure and test distributed rate limiting, ingress request-size cap, concurrency/timeouts, request cost limits and alerting.
- [ ] Inspect production-shaped logs/traces/monitoring for Authorization headers, token values, request bodies, sensitive Task content and internal exceptions.
- [ ] Review SSRF/outbound API boundaries, side-effect idempotency and cancellation behavior for each real Handler.
- [ ] Confirm the development/test anonymous fallback is unreachable from public ingress.
- [ ] If a billing-grade or strict per-owner quota is required, add a dedicated concurrency-safe quota mechanism; Step 21's count-based guard is intentionally a resource guard, not a strict billing/security primitive.

## C. Historical Step 20 rc1 evidence — not valid for current main

Historical candidate:

- Commit: `50e488b893fdbfd63f1a874beedbebb36dc50181`
- Version: `0.2.0.rc1`
- CI: [#37583446432](https://github.com/cuichangquan/a2a-rails/actions/runs/37583446432) — **13/13 PASS**
- Exact artifact security smoke: [#37583446435](https://github.com/cuichangquan/a2a-rails/actions/runs/37583446435) — Rails 8.0/8.1 PASS
- SHA256: `1f44bc740dd90c205fbbe2a90d3e7341a799c3a7b514b265e41a79f5a4f6d8a5`
- Record: [v0.2.0-rc.1 verification record](v0.2.0-rc.1-record.md)

**Do not publish that artifact/version as representing current main after Step 21.**

## D. Exact gates for the next candidate

All items below are required again because Steps 21 and 22 changed runtime code.

- [x] Candidate version selected for verification: `0.2.0.rc2`. The exact candidate commit is recorded only after the preparation PR is merged.
- [ ] Run the Ruby 3.3/3.4/4.0 + Rails 8.0/8.1 regression matrix on that exact candidate.
- [ ] Run the ActiveRecordStore PostgreSQL workflow on the exact candidate.
- [ ] Run production-shaped HTTP security smoke against the exact candidate: fail-closed Agent Card, 401/403, valid Bearer, foreign Task isolation, malformed/oversized requests.
- [ ] Re-run/record official Python/Go interoperability on the exact candidate tree.
- [ ] Re-run/record the pinned official TCK profile on the exact candidate tree.
- [ ] Build the exact `.gem`, inspect package contents/metadata and record SHA256.
- [ ] Install **that exact built artifact** into clean Rails 8.0 and Rails 8.1 hosts.
- [ ] For ActiveRecordStore release claims, install/migrate the exact Gem in a clean DB-backed Rails host and verify restart/multi-instance persistence plus bounded maintenance commands.
- [ ] Obtain explicit approval for tag, GitHub Release and RubyGems publication.
- [ ] After upload, fetch the published Gem and confirm its SHA256 matches the approved artifact.

## Recommended decision record for a real deployment

Record: release commit and Gem SHA256, Rails environment, ingress/TLS configuration, token issuer/audience/revocation policy, principal/tenant ID contract, Task Store type and migration version, retention/prune schedule, quota/collection limits, rate/concurrency/time limits, business authorization checks, tested threat cases, CI/staging evidence, accountable reviewer and date.

## Known limitations

The published v0.1.0 lacks the security controls and ActiveRecordStore described above.

Current unreleased main still does not provide:

- an OAuth2/OIDC server or universal credential verifier;
- universal business/delegated authorization;
- distributed rate limiting;
- streaming;
- an A2A client;
- billing-grade strict per-owner quota enforcement.

MemoryStore remains process-local. ActiveRecordStore must be explicitly selected and operated by the host.

References: [ActiveRecord Task Store](../guides/active-record-task-store.md) · [ActiveJob Task execution](../design/active-job-task-execution.md) · [Production deployment guide](../guides/production-security.md) · [Authentication](../guides/authentication.md) · [Request hardening](../guides/request-hardening.md) · [Roadmap](../../ROADMAP.md) · [Security #11](https://github.com/cuichangquan/a2a-rails/issues/11) · [Step 23 #54](https://github.com/cuichangquan/a2a-rails/issues/54).
