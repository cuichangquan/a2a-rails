# Security hardening — release and deployment readiness checklist

Last reviewed: **2026-10-07 (Step 20)**  
Baseline published release: **a2a-rails 0.1.0** (2026-10-06)  
Candidate: **v0.2.0-rc.1** — source/Gem version `0.2.0.rc1` for artifact verification; not tagged or published.

## Decision

Three decisions are deliberately separated:

| Decision | Status |
| --- | --- |
| Prepare a versioned release candidate for review | **GO after Step 20 documentation audit** |
| Tag / GitHub Release / RubyGems publication | **NO-GO until exact artifact checks + explicit approval** |
| Open public / multi-worker production recommendation | **NO-GO with the default MemoryStore** |

A Gem may be distributed with accurately documented limitations. That does **not** make every deployment topology safe. See [v0.2.0-rc.1 preparation decision](v0.2.0-rc.1-preparation.md).

## Evidence already merged

- [x] [#12 — Step 16-1 threat model](https://github.com/cuichangquan/a2a-rails/pull/12)
- [x] [#13 — Step 16-2 authentication gate](https://github.com/cuichangquan/a2a-rails/pull/13)
- [x] [#15 — Step 16-3 principal ownership and cursor scoping](https://github.com/cuichangquan/a2a-rails/pull/15)
- [x] [#16 — Step 16-4 input limits, log hygiene and cursor cap](https://github.com/cuichangquan/a2a-rails/pull/16)
- [x] [#17 — Step 16-5 Bearer Agent Card security advertisement](https://github.com/cuichangquan/a2a-rails/pull/17)
- [x] [#18 — Step 16-6 production-mode fail-closed smoke / deployment review](https://github.com/cuichangquan/a2a-rails/pull/18)
- [x] Pinned official A2A TCK: **63 passed / 1 failed / 171 skipped / 30 deselected**; remaining CORE-SEND-003 mismatch is [upstream #202](https://github.com/a2aproject/a2a-tck/issues/202), still open as of this review.
- [x] Official Python SDK 1.2.2 + Go SDK v2.6.0 interoperability: [Step 18](../testing/cross-language-interop.md).
- [x] Independent Rails 8 localhost Demo: [a2a-rails-demo](https://github.com/cuichangquan/a2a-rails-demo), real HTTP smoke **16/16 PASS**.
- [x] Recent source-tree Ruby/Rails regression CI: **13/13 PASS** on [Step 19 PR #30](https://github.com/cuichangquan/a2a-rails/pull/30).

## A. Candidate version and consumer compatibility

- [x] Candidate version is **v0.2.0-rc.1** / Gem version **0.2.0.rc1**. VERSION is changed for candidate verification; the candidate is not tagged or published.
- [x] [Upgrade guide from v0.1.0](upgrading-v0.1.0-to-v0.2.md) documents fail-closed production auth, matching Bearer metadata, principal Task isolation, stricter HTTP handling and new opt-in outputs.
- [x] README / CHANGELOG / Roadmap distinguish published v0.1.0 from unreleased source features.
- [x] Exact main candidate commit `50e488b` passed the Ruby 3.3/3.4/4.0 and Rails 8.0/8.1 **13/13** matrix ([run #37583446432](https://github.com/cuichangquan/a2a-rails/actions/runs/37583446432)).
- [x] Candidate version approved for verification; `A2A::Rails::VERSION = "0.2.0.rc1"`. Tag/Release/RubyGems still require separate approval.

## B. Public-production deployment gates

These are deployment gates, not a statement that source code cannot be packaged for evaluation.

- [x] Gem-level tests cover authentication failure behavior and cross-principal Task/read/list/cancel/pagination isolation.
- [ ] Validate the **real host verifier** against expired, forged, revoked, wrong-issuer, wrong-audience and cross-tenant credentials.
- [ ] Verify application business-action authorization inside Handlers/services.
- [ ] Verify HTTPS ingress, trusted proxy / forwarded-header policy, host allowlisting, certificate trust and public Agent Card URL.
- [ ] Configure and test distributed rate limiting, ingress request-size cap, concurrency/timeouts, request cost limits and alerting.
- [ ] Inspect production-shaped logs/traces/monitoring for Authorization headers, token values, request bodies, sensitive Task content and internal exceptions.
- [ ] Review SSRF/outbound API boundaries, side-effect idempotency and cancellation behavior for each real Handler.
- [ ] Choose a **durable owner-aware Task Store with retention/quotas** before restart-safe, multi-worker, replica-based or open-public Task usage. Default MemoryStore does not satisfy this gate.
- [ ] Confirm the development/test anonymous fallback is unreachable from public ingress.

## C. Exact release-candidate artifact gates

All items below are required before any RubyGems publication.

- [x] VERSION approved for candidate verification; exact main candidate commit is `50e488b893fdbfd63f1a874beedbebb36dc50181`.
- [x] Run **13/13 CI** on the exact versioned main candidate — [#37583446432](https://github.com/cuichangquan/a2a-rails/actions/runs/37583446432), **13/13 PASS**.
- [x] Production-shaped HTTP security smoke passed against the **installed exact candidate Gem** on Rails 8.0.5.1 and 8.1.4, including fail-closed Card, 401/403, valid Bearer, foreign Task isolation, malformed/compressed/non-JSON and oversized requests ([#37583446435](https://github.com/cuichangquan/a2a-rails/actions/runs/37583446435)).
- [x] Record protocol evidence against independent clients / pinned official TCK. Re-run if candidate code later changes protocol behavior.
- [x] Built and inspected `a2a-rails-0.2.0.rc1.gem`; SHA256 `1f44bc740dd90c205fbbe2a90d3e7341a799c3a7b514b265e41a79f5a4f6d8a5`.
- [x] Installed **the same uploaded Gem bytes** into clean Rails 8.0 and Rails 8.1 Bundler environments; SHA256 rechecked before each install.
- [x] Installed-artifact production security smoke passed on Rails 8.0/8.1; independent Python/Go and pinned TCK evidence passed on the identical candidate Git tree. See [candidate record](v0.2.0-rc.1-record.md).
- [ ] Obtain explicit approval for tag, GitHub Release and RubyGems publication.
- [ ] After upload, fetch the published Gem and confirm its SHA256 matches the approved artifact.

## Recommended decision record for a real deployment

Record: release commit and Gem SHA256, Rails environment, ingress/TLS configuration, token issuer/audience/revocation policy, principal/tenant ID contract, Task Store/retention behavior, rate/concurrency/time limits, business authorization checks, tested threat cases, CI/staging evidence, accountable reviewer and date.

## Known limitations

The published v0.1.0 lacks the security controls above. Unreleased main still does not provide an OAuth2/OIDC server, universal business authorization, distributed rate limiting, durable Task persistence, asynchronous execution, streaming, or an A2A client. A release candidate must describe those limits rather than imply production completeness.

References: [RC preparation decision](v0.2.0-rc.1-preparation.md) · [Upgrade guide](upgrading-v0.1.0-to-v0.2.md) · [Production deployment guide](../guides/production-security.md) · [Authentication](../guides/authentication.md) · [Request hardening](../guides/request-hardening.md) · [Roadmap](../../ROADMAP.md) · [Security #11](https://github.com/cuichangquan/a2a-rails/issues/11) · [Step 20 #31](https://github.com/cuichangquan/a2a-rails/issues/31).
