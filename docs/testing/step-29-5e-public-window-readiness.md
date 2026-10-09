# Step 29-5e — Temporary public Cloud Run test: operator readiness / NO-GO checklist

> **2026-10-10 release-scope change:** the historical term "public/no-auth
> release gate" in this runbook is **no longer an automatic Gem release
> prerequisite**. It now refers to an *optional separate deployment/security
> experiment* under [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).
> See [Step 29-5t decision](../release/step-29-5t-release-vs-public-deployment-scope.md).
> The experiment remains **NOT APPROVED / NOT RUN**; keep Cloud Run
> IAM-private. The positive **unmodified Client + public DNS/CA HTTPS**
> test against an **IAM-private** server remains accepted as scoped
> *outbound Client interoperability* evidence. The original historical
> operations checklist below remains for reference; it is **not**
> an instruction or permission to execute it.

> **Public/no-auth release gate remains NOT RUN.** The owner-approved, IAM-private
> real GCE outbound Client interoperability smoke **PASSed** on 2026-10-09,
> and the named temporary VM/NAT/firewall resources were subsequently
> **verified deleted**. Do **NOT** change the Cloud Run IAM authentication,
> deploy a public egress workflow or create new billable resources without
> a separate, explicit owner approval. [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90)
> remains OPEN and a2a-rails v0.3.x remains **NO-GO**.

## Ground truth (2026-10-08, operator-provided)

- Dedicated **test** GCP project: `a2a-rails-test`; region: `asia-northeast1`.
- Cloud Run service: `a2a-public-interop-probe`; runtime identity:
  `a2a-interop-probe@a2a-rails-test.iam.gserviceaccount.com`, without project roles.
- **Actual** Cloud Run origin from `status.url` (NOT the URL printed in some
  deploy/update CLI output):
  `https://a2a-public-interop-probe-h6zhnxmqza-an.a.run.app`.
  Never substitute the other URL without verifying it works.
- Configured `A2A_PUBLIC_BASE_URL` is the above origin. Authenticated Agent Card,
  JSON-RPC direct `SendMessage`, Task `SendMessage`, `GetTask`, and Artifact
  retrieval were successful via **ordinary** `A2A::Rails::Client` on Ruby 3.4.11,
  checked out from `main` after
  [PR #96](https://github.com/cuichangquan/a2a-rails/pull/96).
- Public DNS: **8 A + 8 AAAA** in the operator's Cloud Shell observation. The
  Step 29-5d policy validates all answers and pins sockets to an approved IPv4.
- Unauthenticated GET `/` returned **HTTP 403**. Cloud Run is **not public**.
  Do not infer access-control success from `GET /healthz`: the operator got 404
  even when IAM was enabled. Use `/` for the unauthenticated denial check.
- The previous 2026-10-08 Cloud Shell authenticated smoke was distinct from
  the **2026-10-09 dedicated GCE VM** Client-initiated public HTTPS test,
  independently observed with `strace` and fully torn down as recorded below.
  **No public/no-auth Cloud Run exposure was approved or performed.**

## 2026-10-09: restricted GCE / IAM-private outbound Client proof — PASS; teardown PASS

Under separately recorded operator approvals for the short-lived VM,
network controls and IAM-private test, unreleased `A2A::Rails::Client`
ran from an external-IP-less Debian 13 GCE VM to the **original
publicly trusted HTTPS hostname** of the still-IAM-private Cloud
Run Python A2A SDK v1.0 Agent. Independent `strace` of the **real
Client process** observed `connect()` to one of the eight explicitly
allowed public `/32` destinations over TCP 443, without other HTTPS
destinations. Exact origin, pinned DNS, TLS peer and hostname checks,
separate user-token-over-IAP-stdin and Cloud Run IAM enforcement
were preserved throughout. After an operations-only test payload
prefix mismatch was corrected (the controlled fixture accepts
`public-egress-<24 hex>` irrespective of the IAM-private service),
the retry succeeded for the **original Agent Card, JSON-RPC v1.0
direct SendMessage, completed Task, GetTask and Artifact echo**.
One-time user ID tokens were for operator testing only, not
production credentials. [Evidence: Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90#issuecomment-6081842739).

The operator **removed** the temporary tagged EGRESS tcp443 allow
rule, dedicated Cloud NAT, ephemeral VM with auto-delete boot disk,
and tagged IAP SSH ingress rule, then independently checked the
absence of all four groups. The original all-egress DENY remained
enabled, and the original Cloud Run IAM policy remained nonpublic.
The original VPC, subnet, Router and IAM-private Cloud Run were
retained intentionally. [Verified final cleanup: Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90#issuecomment-6081958173).

**What this proves:** real restricted-network Client-originated
HTTPS + authenticated cross-language A2A Message/Task interoperability
and verified cleanup for the named disposable network/VM resources.
**What it does not prove:** public/no-auth externally accessible
Cloud Run, completion of all outbound Client SSRF/negative/TLS,
concurrency or production release gates, zero project charges,
or a durable/production Task Store. The no-auth GitHub manual
workflow here was **not triggered**, and Cloud Run authentication
was **never disabled**. The Python controlled Echo uses an
in-memory Task Store. Incremental USD10 was a planning threshold,
not a hard spend cap; retained Cloud Run and registry artifacts
require separate read-only billing inventory if costs matter.

**Disposition:** Step 29-5e IAM-private GCE Stage D **PASS**;
public-no-auth release gate **NOT RUN**; Issue #90 **OPEN**;
`a2a-rails v0.3.x` **NO-GO**. Do not re-enable NAT/ALLOW or expose
Cloud Run without fresh explicit approval. Historical steps below
are proposals/runbooks for a **different public test**, not
instructions to perform automatically after the IAM-private PASS.

## A. Cost readiness — operator-owned, BEFORE exposure

1. Open [Google Cloud Billing → Budgets & alerts](https://console.cloud.google.com/billing).
   Choose the billing account linked to **`a2a-rails-test`**, then select or
   create a budget scoped specifically to this test project.
2. Choose a spending amount **yourself**, based on acceptable exposure. Configure
   early notifications (for example 50%, 90%, 100%) and verify their recipients.
   Confirm the budget appears for `a2a-rails-test`. Budget/email notifications
   can be delayed and **do not cap charges**; they are not a kill switch.
   If an actual spend-cap budget is offered for the relevant service, review
   eligibility and limitations separately; do not assume a cap exists.
3. Inspect Billing reports and quotas; confirm **no unrelated services** share
   this disposable project. Cloud Run `--max 1` is not an absolute spending cap.
4. Keep Cloud Run `--min 0` while preparing. The Echo Task Store is in memory,
   so the short public smoke may need an approved temporary `--min 1` to
   reduce instance switching (billable idle capacity, not durable persistence).
   Do **not** change it before the owner agrees to that cost.
5. Review images in Artifact Registry after cleanup: deleting a Cloud Run service
   does not automatically delete stored build images or all charges.

Sources: [Google Cloud Billing budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets),
[spend caps and limitations](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps).

## B. Read-only private service readiness

Run from the operator's Cloud Shell. These commands make **no** cloud changes:

```sh
PROJECT=a2a-rails-test
REGION=asia-northeast1
SERVICE=a2a-public-interop-probe

gcloud config get-value project
gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='yaml(status.url,status.conditions,metadata.annotations,spec.template.spec.serviceAccountName,spec.template.spec.containerConcurrency,spec.template.metadata.annotations)'
gcloud run services get-iam-policy "$SERVICE" --project "$PROJECT" \
  --region "$REGION" --format=json

ORIGIN="$(gcloud run services describe "$SERVICE" --project "$PROJECT" \
  --region "$REGION" --format='value(status.url)')"
printf 'Verified origin: %s\n' "$ORIGIN"
curl -sS -o /dev/null -w 'Unauthenticated root HTTP: %{http_code}\n' "$ORIGIN/"
```

**STOP** if the selected project/service or dedicated no-role service account
doesn't match; the service is not Ready; `ORIGIN` differs from the known
working Card URL; unauthenticated root returns anything other than HTTP 403;
`run.googleapis.com/invoker-iam-disabled` is true; or an `allUsers`
`roles/run.invoker` grant exists. Inspect Cloud Run's **Security** tab in
Console because command outputs may omit default annotations. Also verify
the configured image, `A2A_PUBLIC_BASE_URL`, maximum instances and cost
settings before considering exposure.

The service should still require authentication at this stage. Do **not**
test public access by temporarily disabling IAM.

## C. Protected GitHub Actions environment — human configuration

Repository: https://github.com/cuichangquan/a2a-rails

1. Settings → Environments → `a2a-public-egress` (create if absent).
   Restrict deployment branches to **`main`**; enable an authorized required
   reviewer. For a single maintainer, GitHub's **prevent self-reviews** choice
   can prevent the initiator from approving their own run — plan an independent
   approver or explicitly acknowledge the weaker sole-maintainer approval
   model. Do not bypass required checks to force a green run.
2. Environment **variables**, **not secrets**, to set only once a ready endpoint
   is verified and public test execution is explicitly approved:

   | Variable | Exact value |
   | --- | --- |
   | `A2A_PUBLIC_EGRESS_APPROVED` | `controlled-endpoint-no-auth` |
   | `A2A_PUBLIC_CARD_URL` | `https://a2a-public-interop-probe-h6zhnxmqza-an.a.run.app/.well-known/agent-card.json` |
   | `A2A_PUBLIC_EXPECTED_RPC_URL` | `https://a2a-public-interop-probe-h6zhnxmqza-an.a.run.app/python/a2a/jsonrpc` |
   | `A2A_PUBLIC_ALLOWED_ORIGINS` | `https://a2a-public-interop-probe-h6zhnxmqza-an.a.run.app` |

   Do **not** put a Cloud Run IAM token, service-account key, production
   secret, or authorization callback in the public smoke. The current service
   is private, so dispatching the no-auth probe **now will fail**.

## D. Isolated runner and network evidence — operator-owned

- Provision a **fresh isolated disposable** self-hosted runner dedicated to the
  repository, with labels `self-hosted` and `a2a-public-egress`. Restrict
  runner group/repository/workflow access as supported. **Do not** use a
  developer laptop or an existing runner with production credentials, GCP
  keys, SSH agents, sensitive files, or unrestricted network access.
- Firewall: default-deny outbound except approved DNS and the exact observed
  approved destination public IPv4:443, plus narrowly scoped bootstrapping
  destinations necessary for the Actions runner / dependency install. Public
  `run.app` IPs may change: log each DNS answer and fail closed if a changed
  answer cannot be reconciled with firewall policy; do not allow all Google IPs.
- Capture independent network connection telemetry (destination IP/port,
  process/time, or packet trace) from the **actual Client** process. The
  repository's preflight TLS socket is a **different socket** and its destination
  IP is not evidence of the subsequent Client connection. Sanitize logs.
- The workflow is manual on `main`, environment-gated, and has a 10-minute
  job timeout. This timeout **does not** automatically re-private Cloud Run.
  Keep a human operator available during the entire exposure.

## E. Separate owner-approved short public window (NOT AUTHORIZED YET)

Prerequisite **GO / NO-GO** review: A–D complete, owner explicitly approves
the **public no-auth exposure and potential billable resources**, an
immediate rollback operator is present, and a short window (e.g. <=10 minutes)
is agreed. A2A Echo accepts only strict nonce-pattern probes and has 16 KiB
request caps, but **anyone on the internet may still call it**.

Only **after** separate approval, follow the existing
[controlled Cloud Run runbook](step-29-5c-cloud-run-echo-deployment.md)
to temporarily disable the Invoker IAM check. It makes a public endpoint!
Run the protected [manual GitHub workflow](../../.github/workflows/a2a-outbound-public-egress.yml)
on `main`, obtain an approved review, and collect all documented evidence.

At the END or on ANY error, immediately run this **restoration** command
from Cloud Shell (human supervised; no automated shutdown has been set up):

```sh
gcloud run services update a2a-public-interop-probe \
  --project a2a-rails-test \
  --region asia-northeast1 \
  --invoker-iam-check
```

Then repeat the **unauthenticated GET `/` check**, expecting **403**. Inspect
the Security tab and IAM policy too. Cloud Run IAM invoker-check enforcement
is distinct from the `allUsers` IAM binding; ensure no public binding remains.
If the rollback cannot be confirmed, stop and investigate immediately — do
not leave the service public.

Finally remove the disposable service, SA only if unused elsewhere, runner,
temporary variables, and obsolete Artifact Registry images after recording
sanitized evidence. Do not delete unrelated assets.

## F. Evidence / release disposition

Record on [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90):
approver, UTC time window, service ID, exact original Card and RPC URLs,
GitHub run URL and commit SHA, real A/AAAA records, TLS certificate chain
and verification, positive Message + Task + GetTask + Artifact result, **actual
Client process destination IP**, negative SSRF/TLS/auth/concurrency results,
and rollback 403 proof. No tokens, nonce payloads or private keys.

**Current state: IAM-private GCE real Client interop + temporary-resource teardown PASS; public no-auth gate NOT RUN / v0.3.x NO-GO.**
The bounded external-GCE authenticated Client evidence does not by itself
satisfy this separately scoped no-auth public release gate. Stable
released Gem remains **0.2.0**; **do not release 0.3.x** based only
on this experiment.

See [Google Cloud Run public access documentation](https://docs.cloud.google.com/run/docs/authenticating/public)
and [GitHub environment approvals](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).
