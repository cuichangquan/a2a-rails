# Security hardening — release readiness checklist (Step 16)

Last reviewed: **2026-10-07**  
Baseline published release: **a2a-rails 0.1.0** (2026-10-06)  
Development status: Steps 16-1 to 16-5 merged in **unreleased `main`**.

## Decision

**Current global release / open public production status: NO-GO.**

Step 16-6 documents the constraints and confirms tested fail-closed behavior. It does **not** itself authorize a public rollout or a RubyGems push.

## Evidence already merged

- [x] [#12 — Step 16-1 threat model](https://github.com/cuichangquan/a2a-rails/pull/12)
- [x] [#13 — Step 16-2 authentication gate](https://github.com/cuichangquan/a2a-rails/pull/13)
- [x] [#15 — Step 16-3 principal ownership and cursor scoping](https://github.com/cuichangquan/a2a-rails/pull/15)
- [x] [#16 — Step 16-4 input limits, log hygiene, cursor cap](https://github.com/cuichangquan/a2a-rails/pull/16)
- [x] [#17 — Step 16-5 Agent Card security advertisement](https://github.com/cuichangquan/a2a-rails/pull/17)
- [x] [#17 CI: 13/13 checks passed](https://github.com/cuichangquan/a2a-rails/actions/runs/37569260637)
- [ ] Step 16-6 review PR merged and latest 13-job CI green (record the resulting PR and run after merge).

## Release candidate gates — ALL required before a new Gem release

### A. Version and consumer compatibility

- [ ] Agree on the intended version and SemVer impact: production authentication is now fail-closed and Task isolation changes behavior. A patch bump is **not** automatically drop-in compatible.
- [ ] Document an upgrade path from published v0.1.0, including the requirement to configure both the host authenticator and matching Agent Card Bearer metadata.
- [ ] Update `CHANGELOG.md`, README, generator guidance and code samples to distinguish release behavior from unreleased features.
- [ ] Review compatibility with Ruby 3.3/3.4/4.0 and Rails 8.0/8.1.

### B. Security and deployment

- [ ] Host verifier validated with expired, forged, revoked, wrong-issuer, wrong-audience and cross-tenant credentials. Authorization to perform business actions is checked inside Handlers.
- [ ] HTTPS ingress, trusted proxy/forwarded header policy, allowed hosts, certificate trust and public Agent Card URL verified in the target deployment.
- [ ] Rate limiting, ingress request-size cap, concurrency/timeouts, request cost limits and operational alerting configured/tested.
- [ ] Log/tracing/monitoring scrub tested for Authorization headers, token values, request bodies, sensitive Task content and exceptions.
- [ ] Review SSRF, outbound API boundaries, side-effect idempotency and cancellation behavior for each Handler.
- [ ] Verify cross-principal Task access and pagination isolation with tenant-qualified principal IDs.
- [ ] Choose a **durable owner-aware Task Store with Task retention and quotas** before multi-worker, restart-safe or open public production. The default MemoryStore does not satisfy this gate.
- [ ] Confirm no unauthenticated development/test fallback is exposed at the public ingress.

### C. Protocol and artifact verification

- [ ] Run 13/13 GitHub Actions CI jobs on the exact candidate commit.
- [ ] Run a separate Rails production-mode HTTP smoke including Agent Card fail closed, 401/403, valid Bearer, foreign Task isolation and malformed/oversized HTTP bodies.
- [ ] Validate v1.0 protocol conformance and compatibility with an independent official client / TCK (separate prioritized roadmap items; do not claim those checks passed until performed).
- [ ] Build the `.gem` from the exact release commit; verify RubyGems package contents and metadata.
- [ ] Install **that built artifact** into a clean Rails 8.0/8.1 app and repeat staging security smoke. Source-tree tests alone are insufficient.
- [ ] Verify Gem SHA256 before upload and fetched-back SHA256 after publication.
- [ ] Obtain explicit release approval; create tag/GitHub Release/RubyGems publication as separate actions.

## Recommended decision record before launch

Record the following for each deployment: release commit & Gem SHA256, Rails environment, ingress/TLS configuration, token issuer and audience policy, principal/tenant ID contract, Task Store & retention behavior, rate/concurrency/time limits, business authorization checks, tested threat cases, CI + staging links, accountable reviewer and date.

## Known non-goals / limitations

The currently published v0.1.0 Gem lacks the new security controls. The unreleased main line still lacks built-in OAuth2 token issuance/introspection, all-in-one delegated business authorization, distributed rate limiting, durable Task storage and an A2A client. This checklist cannot compensate for missing application-specific enforcement.

References: [Production deployment guide](../guides/production-security.md) · [Authentication setup](../guides/authentication.md) · [Request hardening](../guides/request-hardening.md) · [Roadmap](../../ROADMAP.md) · [Security issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).
