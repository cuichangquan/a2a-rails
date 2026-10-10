# Step 29-5t — Separate Gem release from public/no-auth Cloud Run deployment testing

> **Current 2026-10-10 policy:** [Step 29-5u risk-based OSS Gem release](step-29-5u-risk-based-oss-release-policy.md)
> supersedes the **external-review-as-mandatory-gate** statements in this
> historical Step 29-5t decision. External security audit is now **optional**;
> complete technical/security and package evidence, known Critical/High
> disposition, and explicit owner authorization remain **mandatory**.
> [#113](https://github.com/cuichangquan/a2a-rails/issues/113) is an
> optional community review invitation, **not a reported vulnerability**.
> Public/no-auth Cloud Run separation remains unchanged.

**Owner's direction:** 2026-10-10 JST — separate the earlier proposed *public/no-auth Cloud Run exercise* from the `a2a-rails v0.3.x` **Gem distribution** release criteria. This is a documented **scope decision**, not an independent security sign-off, a waiver of transport/security tests, an authorization to publish, or permission to expose any endpoint.

**Decision:** Public/no-auth Cloud Run exposure is **NOT REQUIRED for Gem release eligibility**, because outbound protocol interoperability with the normal unmodified Client, public DNS, a public-CA TLS certificate, correct socket IP pinning and original Agent Card/JSON-RPC has **already been demonstrated against an IAM-private controlled Cloud Run server**. Disabling the *server's inbound IAM boundary* does not test the outbound Client's DNS/TLS/SSRF parsing or JSON-RPC implementation any further. A public/no-auth exercise would instead test a **different operational security model** (untrusted callers, endpoint abuse, quotas, IAM and billing), tracked independently under [deployment security Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).

## Three decisions: do not conflate

| Question | Decision/gate | Authority and status |
| --- | --- | --- |
| Is outbound `a2a-rails` packaged Gem ready for distribution as **v0.3.x**? | **Release GO/NO-GO:** frozen source + exact `.gem`/SHA256, security and interoperability matrix, no known unresolved Critical/High, compatibility/docs, explicit maintainer publication approval; **external audit optional** | **NOT YET APPROVED** pending mandatory technical checks and explicit owner final approval; [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) remains OPEN |
| Can an organization run an A2A **Server or host application publicly without inbound IAM**? | **Separate public-production deployment GO/NO-GO:** real IdP/token/role and business action authorization, per-user Task access, rate/concurrency/cost controls, durable job/store, TLS/ingress/logging/monitoring, side-effect reconciliation, explicit risk acceptance | **NO-GO by default** on a per-deployment basis; [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) remains OPEN |
| Should the controlled **Cloud Run service** briefly disable IAM to test anonymous access? | **Optional security experiment**, NOT automatic Gem release gate. Requires a **separate explicit owner approval** for exact project/service/time, cost plan, test access, stop/rollback and cleanup; its result cannot certify public deployment alone | **NOT APPROVED; NOT RUN**. Keep existing service IAM-private. No changes to GCP, Cloud Run, Artifact Registry or firewall/NAT |

## Why this separation is technically defensible

- In [Step 29-5e](../testing/step-29-5e-public-window-readiness.md) and [Issue #90 evidence](https://github.com/cuichangquan/a2a-rails/issues/90#issuecomment-6081958173), a specifically controlled GCE VM with scoped egress made genuine `A2A::Rails::Client` outbound requests to the original publicly trusted Cloud Run HTTPS hostname **while IAM stayed private**. The Agent Card, direct Message, Task, GetTask and Artifact passed. Independently observed actual `connect()` destination IPs and original DNS/Host/SNI were recorded, and temporary VM/NAT/firewall resources were torn down.
- IAM is an **access-control layer on the remote server**. It did not change the outbound Client's public IPv4 DNS resolution, pinned TCP socket, TLS CA/hostname verification, request validation, bounded JSON-RPC parsing or handling of signed transport responses. Thus anonymous Cloud Run access is **not a necessary precondition** to verifying those client properties.
- A public server's exposure **does** meaningfully change adversaries and consequences: unauthenticated invocations, token abuse, cross-tenant tasks, resource exhaustion, persistence and financial risk. These require **host/deployment-specific controls**, which a reusable Gem cannot unilaterally attest.
- This narrower scope change **does not claim security certification**. Negative local real-HTTPS SSRF/hostname/proxy/redirect tests, limits, separate Card/RPC bearer isolation, no retry on ambiguous side effects, rich official Python/Go SDK interoperability and installed candidate CI remain part of the **Gem release evidence**. A real production deployment is a separate decision.

## Gem release checklist after scope change

- [x] Normal, unmodified outbound Client against controlled public-DNS + public-CA HTTPS endpoint with IAM-private server; socket pin, Host/SNI, Task/Message evidence recorded; temporary test egress cleaned
- [x] Strict URL/SSRF and DNS negatives, TLS CA/hostname/expired cert, proxy/redirect, token origin binding, error secret masking, bounded transport/JSON and timeout semantics **covered by documented local tests** (scope and limits must be reviewed by the maintainer; optional external feedback welcome)
- [x] Native official Python and Go SDK Message/Task/File/Data/ListTasks/CancelTask tests, including scoped authenticated Go ListTasks and tenant isolation **covered in CI**
- [x] Source-tree-matched `v0.3.0.rc1` private build once, SHA256 and installed Rails/Ruby/PostgreSQL/independent SDK matrix **covered** in [run #38002434735](https://github.com/cuichangquan/a2a-rails/actions/runs/38002434735). Exact review-only source SHA `68572fe7fd6f2f55c98ffdb463e72dd9063f53f7`; private Gem SHA256 `dfad66f8ca992646dedde306669e97b8a8ff94a13a04939d5a44b4dda7630efa`. PR CI ran a GitHub-generated temporary merge commit with **zero source-file diff**, not literally the frozen branch commit
- [ ] **Mandatory maintainer security assessment:** review the full v0.2.0 → candidate diff, source/artifact identity, negative test coverage, known Critical/High findings and residual risks. Record a release-specific GO or NO-GO. **Optional** community reviewer feedback is welcome via [#113](https://github.com/cuichangquan/a2a-rails/issues/113), but its absence is not a known security bug or release blocker.
- [ ] Check remaining security findings; any unresolved Critical/High issue means release NO-GO; document severity triage, what was tested and what was **not** tested
- [ ] **Maintainer's explicit final GO** for precise tag, GitHub Release and RubyGems publication, including signed release notes and post-publication SHA256 `gem fetch` verification
- [x] Public/no-auth **Cloud Run experimental test** is explicitly **out of Gem release scope**, delegated to separate operational/deployment review (#11); no requirement to disable IAM for Gem distribution

**Important:** Checkbox `[x]` reflects evidence of a limited **specific sub-test**, *not* a security certification or independent audit. Source code after candidate freeze, artifact re-build or accepted security fixes require a fresh SHA256 and new review.

## Maintainer security assessment of this narrower scope

The owner has agreed to the separation as a **release-policy direction**.
The **maintainer must review** whether the IAM-private public-HTTPS positive
path, combined with adversarial Client security tests, provides adequate
evidence for this **outbound Gem**. Optional external reviewers may offer
additional assurance and identify gaps; any material unresolved
transport/authorization risk discovered must be addressed before release.
A public/no-auth Cloud Run experiment remains separate, subject to a
written plan and explicit owner authorization.

## Operational reminders

- Keep `a2a-public-interop-probe` IAM-private; never set `allUsers`, disable `run.invoker` enforcement or trigger dormant public-interop workflows without explicit owner approval.
- No new GCP VM/NAT/firewall/Cloud Run test infrastructure or spend is approved through this document. The prior $10 expense discussion was a planning threshold, **not a technical spending cap**.
- Public GitHub release of a **client/library package** is **not** equivalent to enabling an anonymous/public A2A network endpoint.
- Published stable RubyGems `0.2.0` remains unchanged and **v0.3.x is NOT YET APPROVED** until mandatory technical/security gates are recorded and the owner separately authorizes publication; external review is optional. Draft PR [#112](https://github.com/cuichangquan/a2a-rails/pull/112) remains **DRAFT, unmerged**.
