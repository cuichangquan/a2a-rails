#!/usr/bin/env bash
# Read-only inventory for the known Step 29-5e project. NEVER changes cloud state.
set -euo pipefail
PROJECT='a2a-rails-test'
REGION='asia-northeast1'
ROUTER='a2a-public-egress-router'
SERVICE='a2a-public-interop-probe'
DENY='a2a-egress-deny-all'

if [[ "${1:-}" != '--read-only' || $# -ne 1 ]]; then
  echo 'Usage: scripts/gcp-test/inventory.sh --read-only' >&2
  exit 2
fi
command -v gcloud >/dev/null || { echo 'gcloud CLI is required; no changes made' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 is required; no changes made' >&2; exit 2; }

failed=0
printf 'READ ONLY: project=%s region=%s (not a billing/cost estimate)\n' "$PROJECT" "$REGION"
printf '\nCloud Run service (IAM-private expected):\n'
if ! gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='value(metadata.name,status.url,spec.template.spec.serviceAccountName)'; then
  echo 'FAIL: Cloud Run service inventory unavailable' >&2
  failed=1
fi
printf '\nDirect Cloud Run invoker IAM policy (inherited access not covered):\n'
if iam_json="$(gcloud run services get-iam-policy "$SERVICE" --project "$PROJECT" --region "$REGION" --format=json)"; then
  if ! printf '%s' "$iam_json" | python3 -c '
import json, sys
try:
    policy = json.load(sys.stdin)
    public = any(
        b.get("role") == "roles/run.invoker" and
        any(m in ("allUsers", "allAuthenticatedUsers") for m in b.get("members", []))
        for b in policy.get("bindings", [])
    )
    if public:
        print("FAIL: public Cloud Run invoker IAM binding", file=sys.stderr)
        sys.exit(1)
    print("PASS: no public direct roles/run.invoker binding")
except (ValueError, TypeError, AttributeError) as e:
    print("FAIL: invalid IAM policy data", file=sys.stderr)
    sys.exit(1)
'; then failed=1; fi
else
  echo 'FAIL: cannot inspect Cloud Run IAM' >&2
  failed=1
fi

printf '\nOriginal deny rule (must remain enabled):\n'
if deny_json="$(gcloud compute firewall-rules describe "$DENY" --project "$PROJECT" --format=json)"; then
  if ! printf '%s' "$deny_json" | python3 -c '
import json, sys
try:
    rule = json.load(sys.stdin)
    allowed = (rule.get("name") == "a2a-egress-deny-all"
               and rule.get("direction") == "EGRESS"
               and rule.get("disabled", False) is False
               and "0.0.0.0/0" in rule.get("destinationRanges", [])
               and any(d.get("IPProtocol") == "all" for d in rule.get("denied", [])))
    if not allowed:
        print("FAIL: original EGRESS deny-all is missing, disabled or changed", file=sys.stderr)
        sys.exit(1)
    print("PASS: original EGRESS deny-all still configured")
except (ValueError, TypeError, AttributeError) as e:
    print("FAIL: invalid firewall-rule data", file=sys.stderr)
    sys.exit(1)
'; then failed=1; fi
else
  echo 'FAIL: original deny rule missing/unreadable; do not provision' >&2
  failed=1
fi

printf '\nTemporary VM candidates (should be empty):\n'
if ! gcloud compute instances list --project "$PROJECT" --filter='name~^a2a-egress-probe-' \
  --format='table(name,zone,status)'; then failed=1; fi
printf '\nTemporary firewall rule candidates (should be empty):\n'
if ! gcloud compute firewall-rules list --project "$PROJECT" --filter='name~^a2a-egress-probe-' \
  --format='table(name,direction,disabled)'; then failed=1; fi
printf '\nCloud NAT attachments on dedicated router (should be empty):\n'
if ! gcloud compute routers nats list --project "$PROJECT" --region "$REGION" --router "$ROUTER" \
  --format='table(name,natIpAllocateOption)'; then failed=1; fi

printf '\nNOTICE: This inventory is neither a cleanup nor a zero-cost/production-access certification.\n'
printf 'Review project Billing reports, Artifact Registry, proxy/Gateway charges, and inherited IAM separately.\n'
exit "$failed"
