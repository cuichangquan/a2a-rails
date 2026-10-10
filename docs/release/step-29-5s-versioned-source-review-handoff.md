# Step 29-5s — v0.3.0.rc1 versioned-source freeze and external security-review handoff

> **CURRENT RELEASE POLICY (Step 29-5u, 2026-10-10):** [Risk-based OSS release policy](step-29-5u-risk-based-oss-release-policy.md)
> **supersedes** the historical rule below that required independent human
> security sign-off for Gem publication. Independent external review is
> **recommended but optional** under [Issue #113](https://github.com/cuichangquan/a2a-rails/issues/113);
> it is not a known vulnerability and its absence alone is not a release blocker.
> Mandatory: reviewed security/compatibility tests, exact package SHA/provenance,
> no known unresolved Critical/High issues, explicit maintainer GO.
> This document remains a useful **optional reviewer checklist**, not an
> authorization to release. The public/no-auth Cloud Run scope separation
> remains in place and production exposure is **NO-GO by default**.
>
> **Scope update, Step 29-5t (2026-10-10; historical):** The owner chose to separate
> the optional *public/no-auth Cloud Run test* from eligibility to publish
> the outbound **Gem**. [Recorded decision](step-29-5t-release-vs-public-deployment-scope.md)
> relies on the already-tested **unmodified Client → public DNS/CA HTTPS,
> IAM-private** path and leaves all Client SSRF/TLS/auth security checks and
> **independent sign-off** release blocking **at that time**, but Step 29-5u now makes it optional. Production/public ingress
> approval remains separate under [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).
> The historical risk-review text below predates this documented policy revision;
> no Cloud Run IAM changes or new test are authorized.

> **Internal status: review preparation, NOT independent reviewer approval.**
> Maintainer's release issue: [#90](https://github.com/cuichangquan/a2a-rails/issues/90).
> This document and its CI are **not** authority to tag, publish to RubyGems,
> change Cloud Run IAM, create new GCP resources or advertise public-production safety.
> Published stable `0.2.0` remains untouched.

## Two distinct source identities

- **Published stable:** the immutable `v0.2.0` tag and RubyGems `a2a-rails 0.2.0`.
- **Candidate:** `candidate/v0.3.0-rc1` is a **separate review branch**, forked
  from the validated `main` source **after this CI/reviewer-kit PR merges**.
  The *candidate branch's* `lib/a2a/rails/version.rb` must declare
  `VERSION = "0.3.0.rc1"`. The candidate is **not** merged to `main`
  and **not** tagged/published before the mandatory technical checks and explicit owner approval.
  The exact reviewed commit SHA, not the movable branch name, identifies
  the candidate.

### Candidate build contract

[Dedicated private artifact workflow](../../.github/workflows/v0.3-client-private-candidate.yml)
has two intentionally different paths:

| Workflow source ref | Source VERSION | Staging transformation | Meaning |
| --- | --- | --- | --- |
| main, stable compatibility or PR rehearsal | `0.2.0` | Only isolated archive copy changed to `0.3.0.rc1` | **Historical Step 29-5r rehearsal only; not a frozen versioned source** |
| `candidate/v0.3.0-rc1` **push** | **`0.3.0.rc1`** | **NONE** | Real candidate source commit and same-version Gem, built directly from that commit's `git archive` |

Candidate-branch path **fails closed** if the source VERSION does not equal
`0.3.0.rc1`; both paths verify package metadata, all selected Client/Engine
file hashes against checkout, and build a single private artifact once.
Every installed verification job downloads that run's **same artifact**,
verifies `sha256sum -c SHA256SUMS`, and checks recorded `SOURCE_COMMIT`
against `GITHUB_SHA`. The branch's CI run must show
`STAGING_DELTA = NONE` and a complete matrix:

- Ruby 3.3/3.4/4.0 × Rails 8.0/8.1: **6** installed Client-only boot
  (inbound routes 404), installed candidate provenance and production-shaped
  fail-closed Server HTTP security checks.
- PostgreSQL 16 × Rails 8.0/8.1 × host inflection variants: **4**
  installed Gem migration, HTTP auth, restart, race and pruning jobs.
- Independent native HTTPS official Python / Go A2A SDKs: **2**
  installed **exact candidate Gem** end-to-end Text/Data/File,
  Task/GetTask/ListTasks/CancelTask, including test-only Go-authenticated
  owner scoping.
- Build once: **1** job, candidate filename,
  `SHA256SUMS`, `SOURCE_COMMIT`, `STAGING_DELTA`.

The prior Step 29-5r rehearsal was 13/13 PASS and its SHA256 was
`a1333fd69bc4c40a333b1b9bdb8ec84e1b4d8ecde2f0a0af1d9d8205d4fc6be1`.
**Do not assume those bytes or hash equal the newly versioned-source build.**
For a candidate-branch run, record *that run's* artifact ID, exact Git
commit SHA, SHA256, job results and skips in [#90](https://github.com/cuichangquan/a2a-rails/issues/90).

## CI PostgreSQL image-registry outage and runner-local mitigation

The first Step 29-5s prerequisites PR attempt encountered ECR Public
`toomanyrequests` when GitHub Actions tried to pull PostgreSQL 16
**before executing the installed-Gem database tests**. Docker Hub
had separately throttled earlier Step 29-5p jobs. These failures are
**infrastructure setup errors**, not database-test PASS or FAIL.

The four relevant workflows now pin their DB jobs to `ubuntu-24.04`
and use the runner's preinstalled **PostgreSQL 16** instance. Each job
explicitly starts `postgresql.service`, sets only disposable local
test-account credentials, creates `a2a_rails_test`, verifies TCP
connectivity and runs the **unchanged** installed-Gem/PG tests. There
are no Docker/ECR pulls, new GCP services or production DB access.
Runner image installation inventory:
https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md

The reviewer must inspect **final-head green job logs**, not the earlier
failed image-download jobs, and verify the intended PG major version
and all data migrations/locking/restart cases were actually executed.

## Optional independent security review — community contributions welcomed

An AI-generated self-check, a clean CI run, or the single maintainer's
self-approval **is not** an independent security review. If such an optional
review is requested, invite a qualified person or team **not responsible for implementing this candidate**.
They must explicitly inspect the frozen **commit SHA** and the exact
candidate package hash; any code change requires re-freezing and
re-reviewing a new source SHA/artifact.

### Threat model / entry points to verify

| Priority | Review surface | Concrete approval questions and evidence |
| --- | --- | --- |
| P0 | Outbound URL, Agent Card / JSONRPC routing | Can user-controlled Card URL or a malicious Card redirect a Client to private, link-local, metadata, localhost or unapproved RPC origins? Inspect [OutboundPolicy](../../lib/a2a/rails/client/outbound_policy.rb) and [AgentCardResolver](../../lib/a2a/rails/client/agent_card_resolver.rb), URL parsing, mixed A/AAAA, rebind/pin, port policy and all redirection paths. |
| P0 | Pinned HTTPS, CA/SNI/proxies, byte limits | Confirm actual socket connects to approved public IPv4 while preserving URL hostname, Host/SNI/cert verification; proxy env cannot silently reroute, timeouts and payload / Content-Length / compression / JSON-depth bounds cannot be bypassed. Inspect [transport](../../lib/a2a/rails/client/pinned_https_transport.rb), local TLS tests and 29-5e IAM-private public-CA proof. |
| P0 | Credentials / disclosure | Confirm Card and RPC tokens have separately pinned **exact** origin/audience bindings, no callback evaluation on denied target, caller auth failures sanitized, no sensitive request/response body or token leak in Gem-originated errors/instrumentation. Distinguish app/APM/queue/proxy-owned log surfaces; [29-5m](../testing/step-29-5m-credential-log-privacy.md) was **representative**, not exhaustive. |
| P0 | Untrusted JSON-RPC / lifecycle | Check version/id/error shape; strictly oneof Message/Task/Artifact Parts; preserve allowed Data/extension fields without remote URL fetching; verify pagination and ownership. [Python/Go native SDK evidence](../testing/step-29-5q-go-authenticated-list-tasks.md). |
| P0 | Side-effect/timeout and queues | For SendMessage/CancelTask, no automatic retry after may-have-executed timeout; caller message IDs and worker idempotency/reconciliation guidance; real Solid Queue/Sidekiq separate-worker smoke does **not** prove exactly-once remote effects. [29-5o](../testing/queue-adapters.md). |
| P0 | Artifact identity, compatibility | Gem `VERSION`/gemspec agree, Gem and checkout source exactly match package hash; CI-installed Ruby/Rails/PG and independent official SDK interop; ensure released `0.2.0` remains untouched. |
| P0 | Distinct public/no-auth gate and deploy safeguards | 29-5e's unmodified public CA/DNS Client connection targeted **IAM-private** Cloud Run. A separate public/no-auth experiment was **not approved or run**. Require **explicit scoped approval** for such a test, *or* documented formal revision/removal of that release criterion with rationale and accountable acceptance. Do not treat Gem availability as production ingress approval; deployment-specific [#11](https://github.com/cuichangquan/a2a-rails/issues/11) remains open. |

### Reviewer's sign-off format

Any **volunteer independent reviewer** should leave an attributed review note,
preferably on Issue #90 or a dedicated review PR, with:

- Reviewer identity/affiliation, role and independence from candidate changes.
- **Exact candidate Git commit SHA**, candidate `.gem` **SHA256** and
  run/artifact provenance, not only the moving branch name.
- Findings by severity: **Critical/High/Medium/Low/Informational**,
  reproduction or evidence links, and disposition (fixed, accepted by owner,
  deferred with mitigation, unsupported/out-of-scope). Critical/High unresolved
  → **NO-GO**.
- Explicit P0 threat-model coverage (including the separate public/no-auth
  acceptance decision), and what could not be verified.
- Decision: `APPROVE` or `REQUEST_CHANGES` **for that exact reviewed SHA**;
  a clean CI run alone never counts as approval.
- Separate **owner authorization** for tag, GitHub Release and RubyGems
  publication only *after* mandatory technical checks and an explicit owner GO.

## Status and hard stops

The optional independent-review appointment and sign-off are **not performed**
by this preparation and are **not required** for Gem publication under Step 29-5u. No public/no-auth Cloud Run experiment was authorized,
and no GCP cost cap was guaranteed. The preceding Step 29-5q/5r source,
native SDK, worker, installed Gem and PostgreSQL CI are positive
evidence **within their documented bounds**, not blanket production security
certification. Any critical or high unresolved finding keeps the candidate
**NO-GO**. Do not close #90 until an accountable release decision.

**Review branch != published RC; built private Gem != RubyGems push;
maintainer + assistant review != independent audit; optional audit != identified vulnerability.**
