# a2a-rails Roadmap

> Status: updated 2026-10-10 through Step 29-5t documented separation of Gem release gates from optional public/no-auth Cloud Run deployment testing. v0.3.0.rc1 source-tree-matched private installed-candidate verification PASS. Independent external review is recommended **optional** quality work (#113), not a Gem-publication gate; owner sign-off and technical release checks remain open, so v0.3.x is not yet approved.
>
> **Step 21 complete:** [Issue #35](https://github.com/cuichangquan/a2a-rails/issues/35) delivered an optional durable ActiveRecord Task Store, owner-scoped SQL access, row locking, keyset pagination, retention/pruning/quota/payload maintenance, shared Store contract tests and PostgreSQL 16 durability/locking smoke. [Design](docs/design/active-record-task-store.md) · [Guide](docs/guides/active-record-task-store.md). Step 20's `0.2.0.rc1` artifact is historical only; [`0.2.0.rc2`](https://github.com/cuichangquan/a2a-rails/releases/tag/v0.2.0-rc.2) was subsequently verified and published as a **pre-release**. [Step 26](docs/release/v0.2.0-stable-readiness.md) completed the stable-release evidence, [Step 27](docs/release/v0.2.0-publication-record.md) published `0.2.0`, and Step 28 proved that the independent Rails demo runs against that public Gem. Public-production security [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) remains open.

## Current stable baseline — v0.2.0 (released)

- [x] [RubyGems + GitHub Release `0.2.0` published](docs/release/v0.2.0-publication-record.md); public package SHA256 verified.
- [x] A2A v1.0 JSON-RPC integration, Agent Card, Rails generators, synchronous Task lifecycle and opt-in ActiveRecordStore / ActiveJob execution.
- [x] Exact stable artifact verification and independent Rails 8 Echo HTTP smoke using the **published `0.2.0` Gem** ([Step 28 PR #2](https://github.com/cuichangquan/a2a-rails-demo/pull/2)).
- [x] README Quick Start, JP / EN A2A overview PDFs, Zenn / Qiita articles and community submissions.
- [ ] Open public-production approval: deployment-specific controls are still required under [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).

## Step 29-5u — Risk-based OSS release policy: external audit optional (2026-10-10)

- **[Current v0.3.x release/audit policy](docs/release/step-29-5u-risk-based-oss-release-policy.md):** Third-party security audit is **recommended, not mandatory** for Gem publication. **Mandatory**: complete technical security and compatibility tests, frozen-source and exact-artifact provenance, no known unresolved Critical/High code vulnerabilities in release scope, transparent supported/unsupported behavior, and **explicit owner GO**. [Issue #113](https://github.com/cuichangquan/a2a-rails/issues/113) stays OPEN as an **optional community review opportunity**, not a known security bug or release blocker. [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) remains OPEN; release is **not yet approved**. Actual open-public production remains NO-GO by default under #11.

## Step 29-5t — Gem release vs public/no-auth Cloud Run deployment separation (2026-10-10)

- **Owner scope direction:** The optional *public/no-auth Cloud Run* test is **not** a release prerequisite for distributing the outbound Rails Client Gem. Normal **unmodified Client + real public DNS/public-CA HTTPS** verification against an **IAM-private** controlled remote Agent was already evidenced in Step 29-5e; a public/anonymous Agent is a *different deployment threat model*, tracked under [public-production security #11](https://github.com/cuichangquan/a2a-rails/issues/11). [Formal decision and residual security gates](docs/release/step-29-5t-release-vs-public-deployment-scope.md).
- **Independent external security review OPTIONAL:** [Community review request #113](https://github.com/cuichangquan/a2a-rails/issues/113) created for the full `v0.2.0` to frozen `v0.3.0.rc1` delta (exact commit `68572fe7fd6f2f55c98ffdb463e72dd9063f53f7`, private Gem SHA256 `dfad66f8ca992646dedde306669e97b8a8ff94a13a04939d5a44b4dda7630efa`). External review of SSRF/DNS/pinned HTTPS, auth/audience/privacy, bounded transport/Tasks and queues is welcome, but **absence of an outside reviewer alone is NOT a release blocker**; technical checks and known Critical/High defects remain hard gates.
- **Distinct decisions:** GitHub/RubyGems **Gem release NOT YET APPROVED** until technical verification, assessment of known Critical/High findings and *separate owner authorization*; anonymous/public-production deployment **NO-GO** without app/infra-specific controls; optional no-auth Cloud Run experiment **NOT APPROVED / NOT RUN**, requires separate explicit approval and cost/rollback plan. Keep [candidate Draft PR #112](https://github.com/cuichangquan/a2a-rails/pull/112) unmerged, IAM unchanged, and [release gate #90](https://github.com/cuichangquan/a2a-rails/issues/90) OPEN.

## Current next work — Step 29: outbound A2A Client (implementation in progress)

- [Tracking Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75) — design and internal Step 29-3a policy merged; Steps 29-3a–3c merged; Step 29-4a/4b merged (public Rails Client and Client-only Rails mode). Step 29-5 independent outbound verification in progress. **Not yet published or production-approved**.
- [Proposed API / architecture / security-gates document](docs/design/a2a-client.md) — Rails can call remote Agent Card / SendMessage / GetTask / ListTasks / CancelTask, including direct Message and Task response forms.
- **Step 29-1: PASS** — [Client SDK/Demo real HTTP smoke](https://github.com/cuichangquan/a2a-rails/actions/runs/37746771841) (test-only [PR #77](https://github.com/cuichangquan/a2a-rails/pull/77), merged).
- **Step 29-2: public API contract merged** — [PR #78](https://github.com/cuichangquan/a2a-rails/pull/78), [detailed contract](docs/design/a2a-client-public-api.md) and documented fixture-only sanity checks.
- **Step 29-3a: merged** — [PR #79](https://github.com/cuichangquan/a2a-rails/pull/79): strict HTTPS/exact-origin and public-IPv4 DNS preflight. [Details](docs/design/a2a-client-outbound-security.md).
- **Step 29-3b: pinned-IP HTTPS transport merged** — [PR #81](https://github.com/cuichangquan/a2a-rails/pull/81), [Issue #80](https://github.com/cuichangquan/a2a-rails/issues/80): actual socket-IP pinning, Host/SNI certificate verification, redirect and proxy denial, origin-bound credentials and bounded JSON/I/O; tested against a local TLS server. [Details and remaining risks](docs/design/a2a-client-pinned-https-transport.md).
- **Step 29-3c: Agent Card discovery / exact JSONRPC 1.0 interface selection** — [Issue #82](https://github.com/cuichangquan/a2a-rails/issues/82), [design and tests](docs/design/a2a-client-agent-card-discovery.md). Internal Agent Card GET → validated supportedInterfaces URL → pinned JSONRPC POST, optional tenant routing and credential isolation. **Step 29-4a merged** — [PR #85](https://github.com/cuichangquan/a2a-rails/pull/85), [Client API, DTO and error mapping](docs/guides/outbound-a2a-client.md) with executable contract tests. **Step 29-4b merged** — [PR #86](https://github.com/cuichangquan/a2a-rails/pull/86): explicit Client-only Rails Engine configuration and route opt-out with separate-process HTTP tests. **Step 29-5a merged** — [PR #88](https://github.com/cuichangquan/a2a-rails/pull/88) verifies the new outbound Client over real pinned TLS against an independent Demo using **published Gem 0.2.0**, with explicit test-only loopback policy and Agent Card HTTPS URL rewriting. [Scope/limitations](docs/testing/a2a-outbound-independent-demo.md). [Remaining Step 29-5 security gates #87](https://github.com/cuichangquan/a2a-rails/issues/87). **Step 29-5b: official Python and Go SDK **servers** over original Agent Card + native TLS** — [PR #89](https://github.com/cuichangquan/a2a-rails/pull/89), [test/security scope](docs/testing/a2a-outbound-official-sdk-servers.md). Real public Rails Client methods tested via TLS with test-only loopback IP injection; the unmodified card points to each actual native HTTPS RPC path. **Next:** no-injection public HTTPS and full negative security matrix. **NO-GO for production Client** until public no-injection HTTPS and independent server/security verification complete.
- **Step 29-5e restricted public-HTTPS path, IAM-private Agent: PASS (2026-10-09)** — An explicitly approved, no-external-IP GCE VM using scoped eight-/32 TCP443 EGRESS + dedicated Cloud NAT reached the original IAM-private Cloud Run Python A2A SDK v1.0 Agent. Actual ordinary `A2A::Rails::Client` Agent Card, direct Message, Task, GetTask and Artifact **PASS**; independent `strace` observed Client-owned connect to approved IPv4:443 and no unexpected HTTPS IPs. The original DENY and private IAM remained intact. **Teardown PASS**: temp VM+boot disk, NAT and both tag-restricted firewall rules deleted and absence verified. [Operator evidence / final teardown](https://github.com/cuichangquan/a2a-rails/issues/90#issuecomment-6081958173) · [Scope and remaining gates](docs/testing/step-29-5e-public-window-readiness.md). This is **not** a public/no-auth test: Cloud Run was never exposed; no approval to execute the separate public workflow. Remaining Client-negative/release gates and [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) remain OPEN; v0.3.x **NO-GO**.
- **Step 29-5g–j: security regression hardening, PASS (2026-10-09)** — [#99](https://github.com/cuichangquan/a2a-rails/pull/99) DNS/SSRF and immutable pinned IP strings; [#100](https://github.com/cuichangquan/a2a-rails/pull/100) TLS certificate validity, SAN, proxy env and token isolation; [#101](https://github.com/cuichangquan/a2a-rails/pull/101) HTTP streaming/timeout bounds and **truncated Content-Length runtime fix**; [#102](https://github.com/cuichangquan/a2a-rails/pull/102) malformed direct Message Part oneof runtime fix, real HTTPS ambiguous Send/Cancel timeouts and threaded ActiveJob calls. All four PRs merged with their final PR CI matrices successful. **Step 29-5k: release blockers audited** — [evidence-to-gate matrix and next-priority plan](docs/testing/step-29-5k-client-release-gates-audit.md) explicitly distinguish IAM-private public-HTTPS positive proof, local negative gates, incomplete official SDK protocol semantics, multi-process worker testing, privacy/log capture and independent v0.3.x release review. Separate no-auth exposure remains **NOT RUN / requires distinct approval**; [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) OPEN; **v0.3.x NO-GO**. **Steps 29-5l–o merged:** [#104](https://github.com/cuichangquan/a2a-rails/pull/104) nested Task/Artifact/Message Parts, [#105](https://github.com/cuichangquan/a2a-rails/pull/105) concurrent credential and ActiveJob log-sink privacy, [#106](https://github.com/cuichangquan/a2a-rails/pull/106) independent native Python/Go rich Parts and Task state interop (**Go ListTasks remains AUTH_REQUIRED -31401; unverified**), [#107](https://github.com/cuichangquan/a2a-rails/pull/107) actual separate-worker outbound Client HTTPS through Solid Queue/Sidekiq on Rails 8.0/8.1. **Step 29-5p: internal NO-GO release assessment** — [evidence matrix and independent-approval requirements](docs/release/v0.3.x-client-pre-release-security-review.md). Outstanding **P0**: authenticated Go ListTasks decision, exact versioned v0.3 candidate Gem/installed tests, independent security reviewer sign-off, explicit resolution of separately unapproved public/no-auth Cloud Run test criterion, owner publication approval. No new GCP resources or release publication.
- **Step 29-5q: official Go SDK authenticated ListTasks and cross-owner isolation verified** — [PR #109](https://github.com/cuichangquan/a2a-rails/pull/109), [Step 29-5q evidence](docs/testing/step-29-5q-go-authenticated-list-tasks.md). Go `a2a-go/v2 2.6.0` default Task Store requires a nonempty authenticated user name; the prior anonymous `-31401` was not a missing-method result. A test-only official `CallInterceptor` maps two separate scoped fake bearer tokens to real SDK User identities (no bypass of default owner-aware store), and native HTTPS `ListTasks(page_size: 1)` returns a distinct next-page cursor for tenant A, only B's task for tenant B; missing/invalid credentials still get `-31401`; cross-owner GetTask is denied. Python and Ruby/Rails regressions remain green. Historical Step 29-5n/5p matrices retain their timestamped anonymous-only finding. **Still open**: exact 0.3.x release candidate verification, independent security review, separate public/no-auth acceptance decision and explicit owner publication approval. No GCP changes; **v0.3.x NO-GO**.
- **v0.3.0 is only a candidate**; no release, backward-compatibility or production-security claims until tests and release approval.

## Prioritized backlog

| Priority | # | Work item | Outcome | Proposed phase | Status |
| --- | ---: | --- | --- | --- | --- |
| P0 | 1 | [Security hardening](https://github.com/cuichangquan/a2a-rails/issues/11) | Authenticate requests; protect Task reads/lists/cancellation per principal; safe production guidance | Version to decide | **Steps 16-1–16-6 merged; public production NO-GO** |
| P0 | 2 | [Official A2A TCK tests](https://github.com/cuichangquan/a2a-rails/issues/19) | Pin and run official JSON-RPC MUST suite, report results, fix genuine mismatches | Version to decide | **PRs #20–#24 merged; official JSON-RPC MUST: 63 passed / 1 failed / 171 skipped; upstream TCK #202 open** |
| P0 | 3 | [Cross-language interoperability](https://github.com/cuichangquan/a2a-rails/issues/25) | Official Python / Go clients with JSON-RPC 1.0 | v0.1.x proposal | **Complete — PR #27 merged** |
| P0 | 4 | [Runnable Rails example](https://github.com/cuichangquan/a2a-rails/issues/28) | [Separate demo](https://github.com/cuichangquan/a2a-rails-demo), Rails 8 Echo | published RubyGems `0.2.0` | **Complete — Step 28 Demo PR #2 merged; published-Gem CI green** |
| P0 | 5 | GitHub roadmap visibility | Publish and maintain priorities, milestones and next steps | Now | **In progress** |
| P1 | 6 | GitHub Issues organization | Create focused issues for approved upcoming changes, with acceptance criteria | Now | Planned |
| P1 | 7 | [ActiveRecord Task Store](https://github.com/cuichangquan/a2a-rails/issues/35) | Durable owner-scoped Tasks across workers/restarts + lifecycle maintenance | next v0.2 candidate | **Complete — PRs #36–#39** |
| P1 | 8 | [ActiveJob Task execution](https://github.com/cuichangquan/a2a-rails/issues/41) | Run long-running Tasks asynchronously with explicit lifecycle semantics | next v0.2 candidate | **Complete — Steps 22-1–22-10** |
| P0 | 8.5 | [v0.2.0.rc2 candidate verification](https://github.com/cuichangquan/a2a-rails/issues/54) | Fresh exact-candidate verification after Steps 21–22 | v0.2.0.rc2 | **Steps 23–25 complete — rc2 published and verified** |
| P1 | 9 | [A2A Client / Step 29](https://github.com/cuichangquan/a2a-rails/issues/75) | Call remote A2A Agents from Rails | v0.3 proposal | **Design merged; security implementation in progress** |
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

- **Released `0.2.0`:** stable Gem, optional ActiveRecord Task Store / ActiveJob, and [published-Gem Rails demo verification](https://github.com/cuichangquan/a2a-rails-demo/pull/2) are complete; deployment-specific public-production gates remain open.
- **v0.3 proposal:** A2A Client (not yet committed).
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


## Step 22 — ActiveJob Task execution (complete)

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
- Step 22-10 aligns README, design, CHANGELOG, roadmap and release/deployment gates with the implemented behavior. The next work is a **fresh release-candidate decision and verification**, handled separately from Step 22 and requiring explicit approval before any tag/Release/RubyGems publication.
- The proposed worker payload is minimal: Task ID, verified non-secret principal ID, Agent class name and selected Skill ID. The original Message remains in the Task Store.
- Routing is resolved once before enqueue; the background Job executes the selected Skill directly.
- Async execution now uses an atomic `SUBMITTED -> WORKING` execution claim so duplicate queue deliveries cannot both start the same Task.
- Generic automatic Handler retry is intentionally disabled in the initial design because the Gem cannot guarantee exactly-once external business side effects.
- CancelTask remains best effort. A queued canceled Task will not start; arbitrary running Handler code is not force-killed through backend-specific APIs.
- Production async operation requires both a shared/durable Task Store and a durable ActiveJob backend. Issue #11 deployment gates remain open.
- No release version bump or publication is authorized by Step 22.



## Step 23 — v0.2.0.rc2 release-candidate verification (complete)

- [Issue #54](https://github.com/cuichangquan/a2a-rails/issues/54) tracks candidate preparation and verification.
- Candidate source version: `0.2.0.rc2`; user-facing candidate name: `v0.2.0-rc.2`.
- The old Step 20 `0.2.0.rc1` artifact/SHA remains historical evidence only because Steps 21 and 22 changed runtime behavior afterward.
- [x] Fresh Step 23 evidence completed at commit `efdec49daa0ef20edff26d4d198a8afc91567535`: Ruby/Rails matrix, PostgreSQL Task Store, Solid Queue/Sidekiq + HTTP async E2E, installed-artifact production security smoke, Python/Go interoperability, pinned official TCK, exact Gem inspection / Rails 8.0 + 8.1 clean installs, and SHA256 (`d65fdd65003987ece96f0a90a4cf28563929be99d26658deeb275fca30c5d694`). [Evidence record](docs/release/v0.2.0-rc.2-record.md).
- Passing Step 23 makes the candidate reviewable; it does not close deployment-specific Issue #11.
- Tag creation, GitHub Release creation, and RubyGems publication still require separate explicit approval.

## Step 24 — v0.2.0.rc2 release-decision record (complete; historical)

- [Issue #57](https://github.com/cuichangquan/a2a-rails/issues/57) tracks the final checklist reconciliation and release-decision documentation.
- [Final verified candidate record](docs/release/v0.2.0-rc.2-record.md): candidate quality **PASS / GO for publication review**, verified exact Step 23 commit, SHA256 and all test evidence.
- The current main delta after the candidate is limited to `docs/` and not included in the Gem payload; no runtime, gemspec or packaged documentation changed.
- **Step 24's publication approval requirement was satisfied later when the user authorized Step 25.** The historical Step 24 decision did not itself authorize publication.
- After publication, verify downloaded Gem SHA256 and installed-Gem smoke; keep host-specific production-readiness gates in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) open until independently satisfied.

## Step 25 — v0.2.0-rc.2 pre-release publication (complete: 2026-10-08)

- [Issue #59](https://github.com/cuichangquan/a2a-rails/issues/59) tracks the user-authorized publication and post-publication verification.
- **PUBLISHED AND VERIFIED:** annotated tag [`v0.2.0-rc.2`](https://github.com/cuichangquan/a2a-rails/releases/tag/v0.2.0-rc.2) targets verified Step 23 commit `efdec49daa0ef20edff26d4d198a8afc91567535`; GitHub Release is marked **pre-release**, with the original exact `.gem` attached.
- [RubyGems `a2a-rails 0.2.0.rc2`](https://rubygems.org/gems/a2a-rails/versions/0.2.0.rc2) fetched in a fresh temporary directory: published SHA256 **matched** `d65fdd65003987ece96f0a90a4cf28563929be99d26658deeb275fca30c5d694`.
- Published-Gem local clean Bundler install/load/version smoke **PASS** on Ruby 3.4.1 / Rails 8.1.4; this smoke does **not** assert new HTTP Task lifecycle coverage.
- [Final Step 25 publication and verification record](docs/release/v0.2.0-rc.2-record.md) · [release notes](docs/release/v0.2.0-rc.2-release-notes.md) · [publication runbook](docs/release/v0.2.0-rc.2-publication-runbook.md).
- **Next focus:** choose next stable-release criteria and separately review actual production host/deployment controls in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11). Candidate publication does not approve public production.

## Step 26 — v0.2.0 stable-release readiness (complete)

- [Issue #62](https://github.com/cuichangquan/a2a-rails/issues/62) and the [release gate matrix](docs/release/v0.2.0-stable-readiness.md) record completed **A1–A4** Gem-level verification: PostgreSQL/installed-artifact host checks, authentication/isolation, durable queue failure semantics and exact stable-candidate validation.
- Step 26 covered release *readiness*, not publication. The stable release was separately authorized and published in Step 27.
- Host-specific **B1–B4** production deployment gates remain **OPEN / NO-GO by default** under [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).

## Step 27 — v0.2.0 stable publication (complete: 2026-10-08)

- [Publication record](docs/release/v0.2.0-publication-record.md): [GitHub Release v0.2.0](https://github.com/cuichangquan/a2a-rails/releases/tag/v0.2.0) and [RubyGems 0.2.0](https://rubygems.org/gems/a2a-rails/versions/0.2.0) were published and independently verified.
- Immutable artifact SHA256: `497ce4b9d6a8b888d1d4ef0c71df3ab24998ef82fff2455dd6bbe919c22ed700`. Published-Gem install/version and production-shaped HTTP security smoke passed.
- Publication does **not** close production [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).

## Step 28 — independent Rails demo using published 0.2.0 (complete: 2026-10-08)

- [`a2a-rails-demo` PR #2](https://github.com/cuichangquan/a2a-rails-demo/pull/2) merged as `7cb002a63d6cc976b1562ee45e8a260771d7ef1d`: replaced an unreleased Git commit with `gem "a2a-rails", "= 0.2.0"` from RubyGems.
- [PR CI run #37736426834](https://github.com/cuichangquan/a2a-rails-demo/actions/runs/37736426834) and [push CI run #37736412150](https://github.com/cuichangquan/a2a-rails-demo/actions/runs/37736412150): **SUCCESS**. Independent real HTTP smoke **16/16 PASS** covers Agent Card, JSON-RPC v1.0 Task/direct Message, GetTask, ListTasks and expected error cases. CI also verifies published Gem version and RubyGems dependency source plus refusal to start in production.
- Scope is **local-only**, synchronous default Task + MemoryStore. It does **not** prove ActiveRecord/ActiveJob integration in this demo or authorize public production; production [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) remains open.
- **Next proposed development focus:** A2A Client (v0.3 proposal), prioritized against adopter feedback and production security follow-ups.
