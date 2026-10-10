# Step 29-5u — Risk-based OSS Gem release gates and optional external review

> **Owner direction (2026-10-10):** An expensive, independently commissioned security audit is **recommended but NOT mandatory** for publication of the `a2a-rails` Gem. This revises only the project's self-imposed review gate from Step 29-5p/5s/5t, **not** any technical security requirements. RubyGems does not require third-party code audit approval as a universal publication condition.
>
> **Current release decision: NOT YET APPROVED.** There is no automatic GO from changing this policy or passing CI. The owner must make a new, explicit version-specific GO decision after reviewing the final checklist and residual risks. [Release tracker #90](https://github.com/cuichangquan/a2a-rails/issues/90) remains OPEN; [candidate Draft PR #112](https://github.com/cuichangquan/a2a-rails/pull/112) remains unmerged; published stable `0.2.0` remains unchanged.

## Why this is a reasonable OSS policy

The `v0.3.x` outbound Client handles untrusted Agent Card URLs and remotely provided JSON-RPC/Task data, so HTTP/TLS/SSRF/credential and ambiguous-side-effect bugs could be serious. A truly independent security review would provide valuable assurance, but independent reviewers are not currently available to this solo-maintainer project and a paid review may be costly.

**Not independently audited** is a statement about **assurance level**, **not evidence of an identified vulnerability**. Leaving [#113](https://github.com/cuichangquan/a2a-rails/issues/113) open as a voluntary audit opportunity must never be described as a proven unresolved security defect or a blocker to Gem distribution. Conversely, **passing CI is not a formal security certification**, and issues discovered later must be triaged transparently.

## Mandatory v0.3.x package-release gates (release #90)

- [ ] **Pinned release contents and version:** Decide exact version (candidate pre-release or stable), review complete `v0.2.0` → candidate code/API/security/compatibility delta, inspect release notes and breaking changes. Ensure the final source `VERSION`/gemspec/package version agree.
- [ ] **Exact Gem provenance:** Freeze a real source commit; build once, capture SHA256, inspect packaged files and dependencies, verify clean installed Gem paths, confirm Ruby 3.3/3.4/4.0 × Rails 8.0/8.1 and PostgreSQL 16 tests (where applicable) and relevant SDK interoperability on the **actual bytes** planned for distribution. Rebuild/retest if candidate changes; published download SHA256 must be rechecked.
- [ ] **Client and Server security gates:** Review negative and positive automated tests for untrusted URL/Agent Card SSRF, DNS/mixed records/rebind, pinned actual TCP destination, valid CA/Host/SNI TLS, redirect/proxy defenses, Card-vs-RPC secrets and callback origin binding, log/error sanitization, time/size/JSON limits, DTO/Parts validation, tenant isolation, timeout ambiguity/zero automatic retries, queue durability and host-managed idempotency. Record scope and limits, especially test-only fixtures vs real public-CA validation.
- [ ] **Known Critical/High vulnerabilities:** No **known unresolved Critical/High findings in the Gem's release scope**; fix and retest before approval. Distinguish code-level vulnerability from external host configuration risks or optional audit not performed. Do not claim that absence of reported issues proves none exist.
- [ ] **Transparency and support:** Clearly document version support, tested versions, non-goals and production-deployment requirements. Maintain a security reporting process and follow up on credible vulnerability reports. Don't advertise blanket production or security certification.
- [ ] **Owner's explicit and separate release approval:** Document the exact version, frozen commit SHA, artifact SHA256, CI links, open non-blocking limitations, verification status, and a written **GO** before tagging, creating a GitHub Release or pushing to RubyGems. No automatic release or approval by PR merge.

## Recommended, **optional** assurance / community work (#113)

- [ ] Invite qualified external maintainers or users to independently review SSRF/TLS/credential handling and the `v0.2.0` → `v0.3.x` code delta, with precise source SHA and Gem SHA256 when possible.
- [ ] Invite issue/PR feedback or a focused paid assessment later if adoption or risk warrants it; maintainers can prioritize high-risk surfaces instead of requiring an expensive full audit up front.
- [ ] Maintain a clear issue `#113` category "**optional independent security review / community input; NOT a known vulnerability and NOT a release blocker**". Never mark the Gem audited or externally approved unless genuine review evidence exists.

## Three independent decisions

| Decision | Release authority / effect |
| --- | --- |
| **Publish Gem to RubyGems** | Mandatory gates above + explicit maintainer GO; a third-party audit is optional |
| **Operate an internet-accessible production Agent** | Separate host-specific token issuer, business authorization, TLS/ingress, rate/cost/concurrency limits, Task Store and queue operations, observability/incident response; [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) remains OPEN, **public production NO-GO by default** |
| **Expose previously IAM-private Cloud Run without auth** | Optional *separate* experiment, not a Gem-release requirement; requires separately scoped approval, cost plan and rollback; **NOT RUN / NOT AUTHORIZED** |

The outbound Client's prior ordinary public-DNS/public-CA HTTPS verification reached an **IAM-private** controlled server and does not constitute authorization for anonymous inbound production exposure.

## Snapshot of prior technical evidence (not a fresh release decision)

- Frozen candidate branch `candidate/v0.3.0-rc1` at `68572fe7fd6f2f55c98ffdb463e72dd9063f53f7`; only `lib/a2a/rails/version.rb` and `CHANGELOG.md` differ from the then-main baseline (later docs-only policy updates do not change candidate runtime).
- Private candidate Gem `a2a-rails-0.3.0.rc1.gem`, SHA256 `dfad66f8ca992646dedde306669e97b8a8ff94a13a04939d5a44b4dda7630efa`; [13/13 installed Gem/PG/native SDK CI jobs PASS](https://github.com/cuichangquan/a2a-rails/actions/runs/38002434735).
- This was a PR-generated merge-commit checkout `c3ed225555cea4d1491b7a73835a0d5efcd9676c` with **zero source-file diff** versus frozen candidate SHA, **not literally the same Git commit SHA**. Retain distinction and confirm final artifact provenance before publishing.
- A legacy `0.2.0` source-version-locked workflow on the Draft RC1 PR can fail by design. It passed against stable main; **do not claim the whole draft PR check suite is green**.
- Original private CI artifact may expire; historical SHA and results do not mean GitHub still serves those bytes.
- The old Step 29-5p/5s/5t **mandatory independent-signoff** text is retained below or in older documents **only as historical snapshots**. This decision supersedes it wherever release criteria conflict.

**Supersession order:** Step 29-5u release/audit policy is current. Step 29-5t public Cloud Run scope separation still applies. Historical Step 29-5p / 29-5s audit records remain valid as evidence of what was reviewed or proposed at the time, **not as today's Gem publication policy**.
