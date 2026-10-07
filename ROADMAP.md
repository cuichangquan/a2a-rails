# a2a-rails Roadmap

> Status: planning / proposals as of 2026-10-07. These are priorities, not promised release dates or API commitments.
>
> **Step 21 complete:** [Issue #35](https://github.com/cuichangquan/a2a-rails/issues/35) delivered an optional durable ActiveRecord Task Store, owner-scoped SQL access, row locking, keyset pagination, retention/pruning/quota/payload maintenance, shared Store contract tests and PostgreSQL 16 durability/locking smoke. [Design](docs/design/active-record-task-store.md) · [Guide](docs/guides/active-record-task-store.md). Step 20's `0.2.0.rc1` artifact is now **historical only**; current main requires a newly versioned/reverified candidate before publication.

## Current baseline — v0.1.0 (released)

- [x] RubyGems + GitHub Release published.
- [x] Server-first A2A v1.0 JSON-RPC integration, Agent Card, Rails generators, synchronous Task lifecycle.
- [x] CI / packaged-gem verification and a clean Rails Echo smoke test.
- [x] README Quick Start, JP / EN A2A overview PDFs, Zenn / Qiita articles and community submissions.

## Prioritized backlog

| Priority | # | Work item | Outcome | Proposed phase | Status |
| --- | ---: | --- | --- | --- | --- |
| P0 | 1 | [Security hardening](https://github.com/cuichangquan/a2a-rails/issues/11) | Authenticate requests; protect Task reads/lists/cancellation per principal; safe production guidance | Version to decide | **Steps 16-1–16-6 merged; public production NO-GO** |
| P0 | 2 | [Official A2A TCK tests](https://github.com/cuichangquan/a2a-rails/issues/19) | Pin and run official JSON-RPC MUST suite, report results, fix genuine mismatches | Version to decide | **PRs #20–#24 merged; official JSON-RPC MUST: 63 passed / 1 failed / 171 skipped; upstream TCK #202 open** |
| P0 | 3 | [Cross-language interoperability](https://github.com/cuichangquan/a2a-rails/issues/25) | Official Python / Go clients with JSON-RPC 1.0 | v0.1.x proposal | **Complete — PR #27 merged** |
| P0 | 4 | [Runnable Rails example](https://github.com/cuichangquan/a2a-rails/issues/28) | [Separate demo](https://github.com/cuichangquan/a2a-rails-demo), Rails 8 Echo | unreleased Git-pinned Gem source | **Complete — Demo PR #1 merged; CI green** |
| P0 | 5 | GitHub roadmap visibility | Publish and maintain priorities, milestones and next steps | Now | **In progress** |
| P1 | 6 | GitHub Issues organization | Create focused issues for approved upcoming changes, with acceptance criteria | Now | Planned |
| P1 | 7 | [ActiveRecord Task Store](https://github.com/cuichangquan/a2a-rails/issues/35) | Durable owner-scoped Tasks across workers/restarts + lifecycle maintenance | next v0.2 candidate | **Complete — PRs #36–#39** |
| P1 | 8 | [ActiveJob Task execution](https://github.com/cuichangquan/a2a-rails/issues/41) | Run long-running Tasks asynchronously with explicit lifecycle semantics | v0.2 proposal | **Step 22 implementation in progress** |
| P1 | 9 | A2A Client | Call remote A2A Agents from Rails | v0.3 proposal | Planned |
| P2 | 10 | SSE Streaming | Stream Task status/results over A2A-compatible transport | v0.4 proposal | Planned |
| P2 | 11 | Human-in-the-loop | Model INPUT_REQUIRED / AUTH_REQUIRED flows and resume safely | v0.5 proposal | Planned |
| P2 | 12 | ActingFor integration | Optional delegated-authorization integration, never a hard dependency | Future | Planned |
| P3 | 13 | English documentation | Expand international setup, API references and examples | Ongoing | Planned |
| P3 | 14 | OSS contribution / security policy | CONTRIBUTING, SECURITY, support policy and responsible disclosure | Ongoing | Planned |
| P3 | 15 | Community follow-up | Respond to community feedback and collect adopter use cases | Ongoing | Planned |

## Step 16 — Security hardening (#11)

Completed on `main` (unreleased; **not** part of RubyGems v0.1.0):

- [x] [Step 16-1 / PR #12: security threat model and authorization design](https://github.com/cuichangquan/a2a-rails/pull/12).
- [x] [Step 16-2 / PR #13: Rails authentication callback and HTTP gate](https://github.com/cuichangquan/a2a-rails/pull/13).
- [x] [Step 16-3 / PR #15: owner-scoped Task access and pagination](https://github.com/cuichangquan/a2a-rails/pull/15) — restacked replacement for closed #14.
- [x] [Step 16-4 / PR #16: bounded HTTP bodies, defensive input checks, pagination cache cap and safer logs](https://github.com/cuichangquan/a2a-rails/pull/16). Distributed rate limiting remains the host's responsibility.
- [x] [Step 16-5 / PR #17: remaining security tests and explicit Bearer Agent Card security advertisement](https://github.com/cuichangquan/a2a-rails/pull/17).
- [x] [Step 16-6 / PR #18: production deployment security review, release gates and real production HTTP smoke](https://github.com/cuichangquan/a2a-rails/pull/18) — [CI 13/13 green](https://github.com/cuichangquan/a2a-rails/actions/runs/37570771822).
- **Remaining security deployment blockers:** the default MemoryStore is still process-local, but Step 21 now provides an optional owner-aware ActiveRecordStore with retention/quotas and PostgreSQL durability evidence. A real deployment must explicitly select/configure the durable Store and still provide credential verification, business authorization, TLS/ingress controls, distributed rate limits and execution budgets. Public production remains **NO-GO by default**. See [production review](docs/guides/production-security.md) and [release checklist](docs/release/security-hardening-release-checklist.md).


**Reason for priority:** published v0.1.0 is a minimal server, **not** a production-ready authorization solution. The unreleased main branch now has authentication and owner-scoped Task access, but deployment-specific security controls, durability, versioning and artifact validation are still required.

**Step 16 work completed on main (unreleased):**

1. Document threat model: what is public, trusted caller identity, secrets, tenant isolation, proxy assumptions.
2. Specify a generic integration point for host Rails authentication/authorization. Avoid coupling to Devise or one identity provider.
3. Scope Task operations and pagination per authenticated principal; do not treat `taskId` or `contextId` as proof of access.
4. Review input validation, request/response logging, HTTPS and DoS controls.
5. Add negative security tests and Rails integration tests; document compatibility and deployment behavior before release.

**Production warning:** Published v0.1.0 does **not** include authentication/owner scoping. The unreleased main branch adds these protections but is **not automatically production safe**, especially with the default in-memory Task Store. Do not expose it to untrusted clients until the [deployment gates](docs/release/security-hardening-release-checklist.md) are met.

## Step 17 — Official A2A TCK (in progress)

- [Step 17 / PR #20 — pinned official A2A TCK JSON-RPC MUST baseline](https://github.com/cuichangquan/a2a-rails/pull/20).
- [Reproduce and inspect TCK results](docs/testing/official-a2a-tck.md) — official Puma/loopback SUT, pinned TCK commit `263b9cfaf16a554bdfb166a7ba5b67716e946349`.
- **Initial actual test results:** 56 pytest passed, **9 failed**, 170 skipped, 30 deselected. The informational TCK workflow is **not** a conformance certificate.
- **After [Step 17-1 / PR #21](https://github.com/cuichangquan/a2a-rails/pull/21):** 58 passed, **6 failed**, 171 skipped, 30 deselected; actual pinned TCK [run #37572266638](https://github.com/cuichangquan/a2a-rails/actions/runs/37572266638). Remaining failures: Artifact fixtures (4), direct Message fixture (1), upstream CORE-SEND-003 expected-error mismatch (1).
- **After [Step 17-2 / PR #22](https://github.com/cuichangquan/a2a-rails/pull/22):** 60 passed / **4 failed** using legitimate Text/Data Artifact fixtures.
- **After [Step 17-3 / PR #23](https://github.com/cuichangquan/a2a-rails/pull/23):** 62 passed / **2 failed** / 171 skipped / 30 deselected; [official TCK #37573841703](https://github.com/cuichangquan/a2a-rails/actions/runs/37573841703), [13/13 Ruby/Rails CI #37573841693](https://github.com/cuichangquan/a2a-rails/actions/runs/37573841693). The new [File Artifact API](docs/guides/file-artifacts.md) maps binary `raw` or HTTPS `url` outputs to genuine A2A v1 Parts.
- **Step 17-4 / [PR #24](https://github.com/cuichangquan/a2a-rails/pull/24) — merged (`cfdaf0a`):** Added opt-in direct-Message `SendMessage` without changing Task defaults or storing a Task. Final pinned TCK [#37575415912](https://github.com/cuichangquan/a2a-rails/actions/runs/37575415912) improved to **63 passed / 1 failed / 171 skipped / 30 deselected**; final [Ruby/Rails CI #37575415939](https://github.com/cuichangquan/a2a-rails/actions/runs/37575415939) completed **13/13**. Only `CORE-SEND-003` remains, already reported upstream [a2a-tck #202](https://github.com/a2aproject/a2a-tck/issues/202). The TCK workflow is informational; not a full conformance certificate.
- **Step 18 / [PR #27](https://github.com/cuichangquan/a2a-rails/pull/27):** Real Python a2a-sdk 1.2.2 and Go a2a-go/v2 2.6.0 SDK clients succeeded with Agent Card, Task and direct Message, Get/List, terminal CancelTask error and version negotiation; [interop CI #37576586235](https://github.com/cuichangquan/a2a-rails/actions/runs/37576586235) PASS, [Ruby/Rails CI #37576586239](https://github.com/cuichangquan/a2a-rails/actions/runs/37576586239) **13/13**. [Coverage/exclusions](docs/testing/cross-language-interop.md). Not a protocol-wide certification. Published v0.1.0 unchanged.

## Step 18 — official client interoperability (complete)

- [Issue #25](https://github.com/cuichangquan/a2a-rails/issues/25) closed; [PR #27](https://github.com/cuichangquan/a2a-rails/pull/27) merged to main (`c7956cec9d75f71ce0face76e770a2d553316663`).
- Final real [official Python/Go SDK interop #37576849497](https://github.com/cuichangquan/a2a-rails/actions/runs/37576849497) **PASS**. Python a2a-sdk 1.2.2 and Go a2a-go/v2 2.6.0 both worked for Task/direct Message, GetTask, ListTasks, expected terminal cancellation error and v1.0 negotiation.
- Final [Ruby/Rails regression #37576849516](https://github.com/cuichangquan/a2a-rails/actions/runs/37576849516) **13/13 PASS**. [Reproduce and inspect exclusions](docs/testing/cross-language-interop.md).
- **Next proposed:** [Step 19 / Issue #28, runnable Rails example](https://github.com/cuichangquan/a2a-rails/issues/28). Not a full A2A compatibility certificate; RubyGems published v0.1.0 is unchanged.

## Step 19 — standalone runnable Rails example (complete)

- Created [`cuichangquan/a2a-rails-demo`](https://github.com/cuichangquan/a2a-rails-demo) **as a separate repository** from the Gem. Its [PR #1](https://github.com/cuichangquan/a2a-rails-demo/pull/1) was merged (`566e1b7`).
- Ruby **3.4.10**, Rails **8.1.0**, `a2a-rails` **pinned to unreleased source commit `fb99610...`**. No new RubyGems version published.
- The local-only demo provides a complete Echo Agent, Handler and `GET /.well-known/agent-card.json` and `POST /a2a` examples. Real GitHub Actions HTTP verification passed **16/16** smoke checks: Task, direct Message, Get/List and error conditions; also rejects production startup. [Demo CI](https://github.com/cuichangquan/a2a-rails-demo/actions/workflows/smoke.yml).
- No production authentication, durable store or distributed rate limits are claimed. Never expose this anonymous test/demo to public networks; deployment security blockers remain [#11](https://github.com/cuichangquan/a2a-rails/issues/11).

## Step 20 — release-candidate verification (complete)

- [Issue #31](https://github.com/cuichangquan/a2a-rails/issues/31) tracks the completed candidate audit. Main is versioned **`0.2.0.rc1`**; publication is still unapproved.
- [RC preparation decision](docs/release/v0.2.0-rc.1-preparation.md) says **GO for preparing a reviewable candidate**, **NO-GO for publishing without explicit approval**, and **NO-GO for claiming open public production readiness**.
- [Upgrade guide](docs/release/upgrading-v0.1.0-to-v0.2.md) records the v0.1.0 compatibility changes: fail-closed production auth, matching Bearer Agent Card metadata, principal Task isolation, stricter HTTP validation and new opt-in output forms.
- Protocol evidence is already strong enough for candidate planning: pinned TCK **63 pass / 1 upstream failure**, official Python/Go interop PASS and standalone Rails Demo PASS.
- Before any Gem upload: explicitly approve version, rerun exact-candidate 13/13 CI, build/inspect exact `.gem`, clean-install Rails 8.0/8.1, run production-shaped installed-artifact smoke, record SHA256, then obtain explicit publication approval.
- Step 21 subsequently delivered durable owner-aware ActiveRecord persistence with retention/quotas. The old [candidate verification record](docs/release/v0.2.0-rc.1-record.md) remains historical evidence for its exact tree only and **must not** be used to publish current main.

## Suggested release sequence (subject to change)

- **Next release (version TBD):** security changes (potentially incompatible with v0.1.0), conformance evidence, interoperability and reproducible demo. Confirm the release version separately.
- **v0.2 proposal:** ActiveRecord Task Store is complete; next major runtime capability is ActiveJob execution.
- **v0.3 proposal:** A2A Client.
- **v0.4 proposal:** Streaming / SSE.
- **v0.5 proposal:** Human-in-the-loop.
- **Later:** optional ActingFor integration.

## Maintenance

- Track the active step with a GitHub Issue; link it here.
- Keep `main` status and features honest: only mark complete when implementation, tests and docs are merged.
- Prefer small PRs and CI verification over one long-running PR.
- Reprioritize based on real adopter feedback and A2A specification changes.


## Step 21 — ActiveRecord Task Store + lifecycle maintenance (complete)

- [Issue #35](https://github.com/cuichangquan/a2a-rails/issues/35) tracks the completed implementation.
- [Design](docs/design/active-record-task-store.md) preserves the existing `Task::Store` boundary: MemoryStore remains default, ActiveRecordStore is optional, and host custom Stores remain supported.
- Table `a2a_rails_tasks` uses an internal Rails PK plus unique protocol `task_id`; owner/context/state/time are first-class indexed columns and A2A history/artifacts use portable JSON.
- Owner isolation happens in SQL. Transition/cancel use DB row locking.
- Maintenance scope includes terminal-task `expires_at`, bounded batch pruning, per-owner admission quota, stored history/artifact limits and maintenance stats.
- Pagination uses opaque keyset cursors; inserts after page 1 are excluded, while full point-in-time semantics for later state updates are explicitly out of scope.
- ActiveJob/background execution is not part of Step 21.
- [PR #36](https://github.com/cuichangquan/a2a-rails/pull/36) design; [#37](https://github.com/cuichangquan/a2a-rails/pull/37) durable core; [#38](https://github.com/cuichangquan/a2a-rails/pull/38) maintenance; [#39](https://github.com/cuichangquan/a2a-rails/pull/39) shared Store contract + PostgreSQL verification. PostgreSQL 16 [run #37595993690](https://github.com/cuichangquan/a2a-rails/actions/runs/37595993690) PASS, including fork/reconnect persistence and concurrent terminal transition consistency.
- Step 21 changed runtime code after the old `0.2.0.rc1` candidate. A fresh versioned candidate and exact-artifact verification are required before any publication.


## Step 22 — ActiveJob Task execution (design in progress)

- [Issue #41](https://github.com/cuichangquan/a2a-rails/issues/41) tracks the design and implementation.
- [Design](docs/design/active-job-task-execution.md) keeps synchronous execution as the default and makes async execution opt-in at global / Agent / Skill scope.
- Step 22-2 implements the configuration surface and `Skill > Agent > global` resolution.
- Step 22-3 ([PR #44](https://github.com/cuichangquan/a2a-rails/pull/44)) adds the `ExecutionPlan`, Gem-owned ActiveJob class, async `SUBMITTED` response path, route-once Skill execution, minimal Job payload, and atomic execution claim for MemoryStore/ActiveRecordStore.
- Step 22-4 ([PR #46](https://github.com/cuichangquan/a2a-rails/pull/46)) constrains Job arguments to validated Task/principal/Agent/Skill identifiers and verifies foreign-principal isolation.
- Step 22-5 ([PR #47](https://github.com/cuichangquan/a2a-rails/pull/47)) hardens enqueue success/failure handling and pins the no-generic-Handler-retry policy; the Task job opts out of transaction-deferred enqueue.
- Step 22-6 pins cancellation semantics: a canceled SUBMITTED Task cannot be claimed later, while WORKING cancellation is logical/best-effort and late completion cannot overwrite CANCELED.
- Step 22-7 pins duplicate suppression during WORKING and after terminal outcomes, stable Task idempotency keys, and PostgreSQL cross-process claim contention. Business side effects and distinct SendMessage submissions require host idempotency.
- Step 22-8 adds real Solid Queue / Sidekiq adapter and separate-worker smoke coverage on Rails 8.0 / 8.1; queue payloads, outcomes, duplicate/canceled delivery, and queued work after worker restart. See [reproduction and limits](docs/testing/queue-adapters.md).
- Step 22-9 ([PR #51](https://github.com/cuichangquan/a2a-rails/pull/51)) verifies loopback HTTP async E2E with separate Web/worker processes: SendMessage SUBMITTED, Get/List WORKING and terminal outcomes, owner isolation, route-once, cancellation and Web/worker restart persistence.
- Next: **22-10 Docs / roadmap / release gates**.
- The proposed worker payload is minimal: Task ID, verified non-secret principal ID, Agent class name and selected Skill ID. The original Message remains in the Task Store.
- Routing is resolved once before enqueue; the background Job executes the selected Skill directly.
- Async execution now uses an atomic `SUBMITTED -> WORKING` execution claim so duplicate queue deliveries cannot both start the same Task.
- Generic automatic Handler retry is intentionally disabled in the initial design because the Gem cannot guarantee exactly-once external business side effects.
- CancelTask remains best effort. A queued canceled Task will not start; arbitrary running Handler code is not force-killed through backend-specific APIs.
- Production async operation requires both a shared/durable Task Store and a durable ActiveJob backend. Issue #11 deployment gates remain open.
- No release version bump or publication is authorized by Step 22.

