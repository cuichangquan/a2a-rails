# Step 33 — Cost-conscious A2A Client verification (operator guide)

**Scope:** Reduce repeat-verification cost for published `a2a-rails 0.3.0` without creating new GCP resources or public exposure. The 2026-10-09 IAM-private GCE HTTPS test and verified temporary VM/NAT/firewall teardown remain historical evidence, **not** permission to recreate the environment. See [Step 29-5e](step-29-5e-public-window-readiness.md) and the [independent stable 0.3.0 Client demo](https://github.com/cuichangquan/a2a-rails-client-demo).

## Choose the least expensive relevant layer

| Layer | When | Evidence | Cost boundary |
| --- | --- | --- | --- |
| Docs-only / Level 1 | Documentation, lightweight scripts | Review content, run offline script tests | No GCP |
| Level 2 | Client/Server/SDK API or compatibility | Published Gem, independent Rails Client ↔ Server pinned-TLS tests, relevant SDK/PG/security CI | GitHub Actions minutes, no new GCP |
| Level 3 review | DNS/SSRF/TLS, network egress, authentication boundaries | Level 2 + decide if missing real-world evidence warrants new controlled GCP verification | **Separate approval before new cloud cost** |

The classifier makes an **advisory recommendation**. It neither disables existing CI nor overrides required branch checks, security gates, release provenance or explicit maintainer approval. A Gem release always follows its full release matrix, even if the changed paths appear documentation-only.

```bash
bash scripts/verification/plan.sh --files README.md docs/guides/outbound-a2a-client.md
bash scripts/verification/plan.sh --files lib/a2a/rails/client/outbound_policy.rb
bash scripts/verification/test.sh
bash scripts/gcp-test/test.sh
```

For ordinary file names on a Git branch, optionally compute changed paths:

```bash
git diff --name-only origin/main...HEAD | xargs -r bash scripts/verification/plan.sh --files
```

For paths containing spaces, use explicitly quoted arguments rather than the example `xargs` pipeline.

Reuse CI first:
- [Client-only Rails tests](https://github.com/cuichangquan/a2a-rails-client-demo/actions/workflows/test.yml)
- [Independent stable-to-stable Rails HTTPS interop](https://github.com/cuichangquan/a2a-rails-client-demo/actions/workflows/interop-https.yml)
- [Existing Gem SDK/security/PostgreSQL workflows](https://github.com/cuichangquan/a2a-rails/actions)

Isolated TLS with a loopback-only test bridge and ephemeral CA is **not** equivalent to a public-DNS/public-CA no-injection connection.

## Phase A/B — decide scope before paying for Phase C/D

1. Record the changed behavior, security boundary and missing evidence.
2. Reuse already-green offline, independent Gem and security-negative tests when relevant.
3. Reuse the existing [IAM-private GCE real HTTPS evidence](step-29-5e-public-window-readiness.md) if the relevant runtime/network assumptions remain unchanged. Do not imply that older results prove a new change.
4. If a new GCP probe remains necessary, document the exact owned resources, approved spend/window, budget notifications, rollback names and data to capture **before** provisioning. Alerts do not guarantee a hard spending cap.

## Phase C/E — read-only safety inventory, no cloud mutations

**Default is NO CLOUD CHANGE.** Step 33 scripts contain **no GCP create, update, delete or IAM-mutating commands** and cannot provision or tear down VMs. The last verified operator cleanup removed its temporary VM, disk, Cloud NAT and temporary ingress/egress firewall rules; the original all-EGRESS DENY and IAM-private Cloud Run were retained.

On an already authenticated operator machine / Cloud Shell:

```bash
bash scripts/gcp-test/inventory.sh --read-only
```

The hard-coded read-only inventory is scoped to project `a2a-rails-test`, region `asia-northeast1`. It checks the original `a2a-egress-deny-all` EGRESS firewall rule, *direct* Cloud Run invoker policy (rejects `allUsers` and `allAuthenticatedUsers`), reports temporary `a2a-egress-probe-` VM/firewall candidates and Cloud NAT attachments to `a2a-public-egress-router`. A missing deny policy or public Cloud Run binding returns failure. It does **not** check all inherited IAM/ingress network paths and does not calculate costs. A permission error means **stop and investigate**, not provision a replacement.

If a fresh, owner-approved Level 3 experiment is needed, follow the [controlled egress runbook](step-29-5c-egress-runbook.md). Before building Phase C automation, separately approve an exact **new resource manifest and teardown sequence**, including lifetimes, exclusive ownership and budget. Never use wildcard deletion, change Cloud Run to public/no-auth or loosen the original deny rule. After manual teardown, repeat the inventory and review Billing reports and Artifact Registry/proxy/Gateway charges; deleting a VM alone is not proof of zero costs.

## Next possible optimization

After reviewing branch protection/required CI, consider path-based conditions for clearly documentation-only PRs. This step deliberately **does not** disable expensive CI jobs. Measure GitHub Actions minutes and actual GCP Billing before claiming savings.
