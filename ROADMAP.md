# a2a-rails Roadmap

> Status: planning / proposals as of 2026-10-07. These are priorities, not promised release dates or API commitments.
>
> **Next:** [#11 Security hardening (Step 16)](https://github.com/cuichangquan/a2a-rails/issues/11).

## Current baseline — v0.1.0 (released)

- [x] RubyGems + GitHub Release published.
- [x] Server-first A2A v1.0 JSON-RPC integration, Agent Card, Rails generators, synchronous Task lifecycle.
- [x] CI / packaged-gem verification and a clean Rails Echo smoke test.
- [x] README Quick Start, JP / EN A2A overview PDFs, Zenn / Qiita articles and community submissions.

## Prioritized backlog

| Priority | # | Work item | Outcome | Proposed phase | Status |
| --- | ---: | --- | --- | --- | --- |
| P0 | 1 | [Security hardening](https://github.com/cuichangquan/a2a-rails/issues/11) | Authenticate requests; protect Task reads/lists/cancellation per principal; safe production guidance | v0.1.x | **In progress — Step 16-6** |
| P0 | 2 | Official A2A TCK tests | Verify interoperability/conformance against the current A2A test suite | v0.1.x | Planned |
| P0 | 3 | Cross-language interoperability | Validate calls from official Python / Go clients and version negotiation | v0.1.x | Planned |
| P0 | 4 | Runnable Rails example | Provide a reproducible Rails Agent demo outside the Gem repo | v0.1.x | Planned |
| P0 | 5 | GitHub roadmap visibility | Publish and maintain priorities, milestones and next steps | Now | **In progress** |
| P1 | 6 | GitHub Issues organization | Create focused issues for approved upcoming changes, with acceptance criteria | Now | Planned |
| P1 | 7 | ActiveRecord Task Store | Persist Tasks across Rails processes and restarts | v0.2 proposal | Planned |
| P1 | 8 | ActiveJob Task execution | Run long-running Tasks asynchronously with explicit lifecycle semantics | v0.2 proposal | Planned |
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
- [ ] [Step 16-6 / Draft PR #18: production deployment security review, release gates and production HTTP smoke](https://github.com/cuichangquan/a2a-rails/pull/18) — **in progress**; public production remains NO-GO pending durable Task storage and deployment-specific controls.


**Reason for priority:** published v0.1.0 is a minimal server, **not** a production-ready authorization solution. The unreleased main branch now has authentication and owner-scoped Task access, but further security review and deployment controls are required.

**Immediate work:**

1. Document threat model: what is public, trusted caller identity, secrets, tenant isolation, proxy assumptions.
2. Specify a generic integration point for host Rails authentication/authorization. Avoid coupling to Devise or one identity provider.
3. Scope Task operations and pagination per authenticated principal; do not treat `taskId` or `contextId` as proof of access.
4. Review input validation, request/response logging, HTTPS and DoS controls.
5. Add negative security tests and Rails integration tests; document compatibility and deployment behavior before release.

**Production warning:** Until a supported and tested authentication/authorization integration is available, do **not** expose the Gem's A2A Task endpoint to untrusted clients. For local demos, follow the Quick Start; for production experiments, restrict access at the network/application boundary and review your host application's security policy.

## Suggested release sequence (subject to change)

- **v0.1.x:** security, conformance tests, interoperability, reproducible demo.
- **v0.2 proposal:** persistent Task Store + ActiveJob.
- **v0.3 proposal:** A2A Client.
- **v0.4 proposal:** Streaming / SSE.
- **v0.5 proposal:** Human-in-the-loop.
- **Later:** optional ActingFor integration.

## Maintenance

- Track the active step with a GitHub Issue; link it here.
- Keep `main` status and features honest: only mark complete when implementation, tests and docs are merged.
- Prefer small PRs and CI verification over one long-running PR.
- Reprioritize based on real adopter feedback and A2A specification changes.
