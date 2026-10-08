# Step 29-5c — controlled Cloud Run public HTTPS Echo deployment

> **Deployment is manual and temporary.** This repository does not provision or own any Google Cloud project, DNS name, certificate, protected GitHub Environment or network-filtered CI runner. Completing the files in this directory is **not** proof of public egress. Publication of `a2a-rails` v0.3.x remains NO-GO; [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) stays OPEN.

## Why Cloud Run

Google Cloud Run provides a stable, Google-managed **HTTPS `run.app` hostname** with publicly trusted TLS. The public TLS connection terminates at the managed Cloud Run endpoint. This is a real public HTTPS endpoint, not the localhost bridge or self-signed CA used by Step 29-5a/5b. The internal Cloud Run container listens on HTTP on its private `PORT` as required by the platform.

The image in `spikes/a2a_client_v03/controlled_public_echo/` runs an independent **official Python `a2a-sdk==1.2.2`** JSON-RPC v1.0 Agent. It serves its *original, unmodified* Card and declared RPC URL using the explicit, exact `A2A_PUBLIC_BASE_URL` origin. It supports nonce-echoing `direct:` Message and `task:` Task + Artifact, matching `public_https_probe.rb`.

### Safeguards and limits

- Startup without `A2A_PUBLIC_BASE_URL` is **private-bootstrap only**: `/healthz` works, but the Card/RPC paths return 404. Do not make the service public in this state.
- Configured origin must exactly match `https://*.run.app` without path, port, query, fragment or credentials. The application rejects malformed origins and never guesses one from untrusted Host headers.
- Only `GET /healthz`, `GET /.well-known/agent-card.json` and `POST /python/a2a/jsonrpc` are reachable. RPC body is capped to **16 KiB**, including chunked requests; unsupported content type/encoding is rejected. All other paths return 404.
- Only controlled probe requests matching `direct: public-egress-<24 hex>` or `task: public-egress-<24 hex>` are echoed. No model execution, secrets, database, production API permissions or user information. Request/response access logs are disabled in the container.
- `InMemoryTaskStore` is **ephemeral and not durable**. Use one minimum and maximum instance **only for the short test window** to reduce GetTask loss between requests. Cloud Run minimum instances have idle cost and do not guarantee persistence or instance lifetime; do not claim high-availability behavior or use as a production Task Store.
- **Public no-auth service means anyone on the internet can send requests.** Set a Google Cloud billing budget/alerts, review project quotas, keep the test window short and delete the service immediately after testing. Scaling limit is a cost guard, **not a hard billing cap** and can be briefly exceeded. `--min 1` incurs charges even when idle; change to `--min 0` only if you accept the extra risk of losing in-memory Tasks across requests. Do not let the test process accept sensitive inputs.
- **Use an explicit dedicated runtime service account with no granted project roles.** Without `--service-account`, Cloud Run normally uses the project's Compute Engine default service identity, which can have broader inherited permissions. The Echo Agent does not need access to any GCP APIs; never give it Editor, Cloud Run Admin, storage, database, or production credentials. The human deployer separately needs Cloud Run deploy and `iam.serviceAccounts.actAs` permissions.

## Phase 1: provision an initially PRIVATE Cloud Run service

Requirements: `gcloud` CLI logged into a dedicated GCP test project; Cloud Run, Cloud Build and Artifact Registry APIs enabled; billing account and quota limits reviewed. Do not use production GCP project credentials. The following commands perform **real cloud writes and incur possible charges**; inspect before executing.

From the root of the cloned `a2a-rails` repository:

```sh
# Substitute your own dedicated testing project.
export PROJECT_ID="YOUR_TEST_GCP_PROJECT_ID"
export REGION="asia-northeast1"
export SERVICE="a2a-public-interop-probe"
export APP_DIR="spikes/a2a_client_v03/controlled_public_echo"
export SA_NAME="a2a-interop-probe"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Verify the intended account and target project BEFORE making cloud changes.
gcloud auth list --filter="status:ACTIVE"
gcloud projects describe "$PROJECT_ID" --format="value(projectId,name)"
# STOP if this is an existing production/Firebase application project.
# A failed list (for example missing permissions) is a STOP, not evidence
# that the requested service name is available.
existing_services="$(gcloud run services list \
  --project "$PROJECT_ID" --region "$REGION" \
  --format="value(metadata.name)")" || { echo "STOP: cannot list Cloud Run services" >&2; exit 1; }
if printf '%s\\n' "$existing_services" | grep -Fx -- "$SERVICE"; then
  echo "STOP: existing Cloud Run service; choose a fresh name" >&2
  exit 1
fi

gcloud config set project "$PROJECT_ID"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com iam.googleapis.com

# A NEW identity with NO project IAM roles. The deployment principal must
# separately possess iam.serviceAccounts.actAs on this identity.
gcloud iam service-accounts create "$SA_NAME" \
  --project "$PROJECT_ID" \
  --display-name="Ephemeral Step 29-5c Echo Agent (no project roles)"
gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" \
  --format="value(email)"

# Private-first; do not deploy into an existing public service.
gcloud run deploy "$SERVICE" \
  --source "$APP_DIR" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --service-account "$SA_EMAIL" \
  --ingress all \
  --invoker-iam-check \
  --cpu 1 --memory 512Mi \
  --concurrency 1 --min 1 --max 1 --timeout 15s
```

This initial revision has **no** `A2A_PUBLIC_BASE_URL`, and does not expose A2A routes. Cloud Run initially requires IAM-authenticated callers; no unauthenticated public traffic should reach it. Verify IAM/service access settings before proceeding.

**IAM prerequisite:** If deploying with the dedicated service identity fails because of `iam.serviceAccounts.actAs`, have the GCP administrator grant `roles/iam.serviceAccountUser` to the deployment principal **on this particular identity only**; do not grant project-wide Editor. If an `a2a-interop-probe` identity already exists, review its IAM roles and ownership instead of blindly reusing it. Service-account creation and attachment are real cloud writes, not GitHub repository operations.

## Phase 2: configure the actual platform-issued public URL, still PRIVATE

```sh
export PUBLIC_BASE_URL="$(gcloud run services describe "$SERVICE" \
  --project "$PROJECT_ID" --region "$REGION" \
  --format='value(status.url)')"
printf 'New controlled Cloud Run URL: %s\n' "$PUBLIC_BASE_URL"
# IMPORTANT: do not use .test, localhost, private IPs or a fabricated URL.

gcloud run services update "$SERVICE" \
  --project "$PROJECT_ID" --region "$REGION" \
  --update-env-vars="A2A_PUBLIC_BASE_URL=$PUBLIC_BASE_URL" \
  --invoker-iam-check
```

Check `PUBLIC_BASE_URL` is a concrete `https://*.run.app` **origin without trailing slash**. Inspect the environment and IAM in Cloud Console while it remains private. The exact Card and RPC URLs will be:

```text
CARD_URL:  <PUBLIC_BASE_URL>/.well-known/agent-card.json
RPC_URL:   <PUBLIC_BASE_URL>/python/a2a/jsonrpc
```

Do not put these URLs into CI until the service is known to be owned by the test project and ready.

## Phase 3: explicitly allow temporary public access

Only when the security owner has reviewed billing limits, TTL, public exposure, allowed network egress and the test environment:

```sh
gcloud run services update "$SERVICE" \
  --project "$PROJECT_ID" --region "$REGION" \
  --no-invoker-iam-check
```

This is a conscious public-access change. It is **not** performed by any GitHub PR workflow, and it is not a command ChatGPT has executed.

Inspect the Card without request credentials:

```sh
curl --fail --silent --show-error \
  "$PUBLIC_BASE_URL/.well-known/agent-card.json"
```

The returned Agent Card must advertise exactly `$PUBLIC_BASE_URL/python/a2a/jsonrpc` under `supportedInterfaces`. **Do not modify** the Card to make the test pass.

## Phase 4: configure the protected outbound Client CI

Create the **protected** GitHub Actions Environment `a2a-public-egress`, restrict it to `main`, and require an authorized reviewer. Set these environment variables **only after** the real service URL is known:

| GitHub Environment variable | Value |
|---|---|
| `A2A_PUBLIC_EGRESS_APPROVED` | `controlled-endpoint-no-auth` |
| `A2A_PUBLIC_CARD_URL` | `$PUBLIC_BASE_URL/.well-known/agent-card.json` |
| `A2A_PUBLIC_EXPECTED_RPC_URL` | `$PUBLIC_BASE_URL/python/a2a/jsonrpc` |
| `A2A_PUBLIC_ALLOWED_ORIGINS` | exact `$PUBLIC_BASE_URL` |

Substitute the **literal resolved URL** for `$PUBLIC_BASE_URL` in GitHub environment variables. Do **not** store shell variable references there.

Provide a dedicated, isolated **self-hosted** GitHub Actions runner labeled `a2a-public-egress`, with egress firewall allowing only approved DNS resolution and actual target IP:443 traffic, without production credentials. The repository workflow intentionally does **not** fall back to an unrestricted `ubuntu-latest` runner.

Run **Actions → Step 29-5c controlled public HTTPS outbound Client egress → Run workflow** on `main`, then approve the environment. It executes:

1. Original public IPv4 DNS + system CA TLS preflight (independent socket).
2. Unmodified `A2A::Rails::Client.new` direct Message echo.
3. Remote Task + GetTask + Artifact echo.

Record the actual **Rails Client** socket destination IP separately through trusted runner firewall or packet capture; the preflight IP is only evidence for its own socket. Check DNS A/AAAA: production `OutboundPolicy` currently rejects IPv6 and mixed A/AAAA; do not inject a fake resolver or weaken the blocklist to pass. A dual-stack result means **blocked pending a separate IPv6 security decision**, not PASS.

Attach sanitized workflow link, real endpoint paths, certificate chain/issuer/fingerprint, DNS answers, actual Client dialed IP and commit SHA to Issue #90. Never print tokens, request Parts or remote bodies.

## Phase 5: revoke public access and clean up

Immediately after collecting evidence, close the test window:

```sh
gcloud run services update "$SERVICE" \
  --project "$PROJECT_ID" --region "$REGION" \
  --invoker-iam-check
gcloud run services delete "$SERVICE" \
  --project "$PROJECT_ID" --region "$REGION"
# Remove only the service account specifically created for this disposable test,
# after confirming it is not attached to any other service.
gcloud iam service-accounts delete "$SA_EMAIL" \
  --project "$PROJECT_ID"
```

Remove the dedicated runner, environment variables and obsolete test artifacts, and review Cloud Run/Artifact Registry billing. Do not assume deleting Cloud Run also deletes built images, Artifact Registry artifacts or project costs.

## Acceptance decision

A successful container build and local tests **only** prove the source fixture runs. A real public connection is only PASS after a dated protected manual run and independent network evidence. This environment is **not** production-ready and provides no authorization to release RubyGems v0.3.x.
