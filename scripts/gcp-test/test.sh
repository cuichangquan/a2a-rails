#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
script='scripts/gcp-test/inventory.sh'
if bash "$script" >/dev/null 2>&1; then
  echo 'FAIL: inventory allowed invocation without --read-only' >&2; exit 1
fi
mockdir="$(mktemp -d)"
trap 'rm -rf "$mockdir"' EXIT
cat > "$mockdir/gcloud" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS_FILE"
case "$*" in
  *'get-iam-policy'*)
    if [[ "${MOCK_PUBLIC:-0}" == 1 ]]; then
      echo '{"bindings":[{"role":"roles/run.invoker","members":["allUsers"]}]}'
    else
      echo '{"bindings":[]}'
    fi ;;
  *'firewall-rules describe'*)
    if [[ "${MOCK_DENY_DISABLED:-0}" == 1 ]]; then
      echo '{"name":"a2a-egress-deny-all","direction":"EGRESS","disabled":true,"destinationRanges":["0.0.0.0/0"],"denied":[{"IPProtocol":"all"}]}'
    else
      echo '{"name":"a2a-egress-deny-all","direction":"EGRESS","disabled":false,"destinationRanges":["0.0.0.0/0"],"denied":[{"IPProtocol":"all"}]}'
    fi ;;
  *'services describe'*) echo 'a2a-public-interop-probe https://example.run.app' ;;
  *) echo 'No matching resources' ;;
esac
MOCK
chmod +x "$mockdir/gcloud"
export CALLS_FILE="$mockdir/calls.log"
export PATH="$mockdir:$PATH"
bash "$script" --read-only > "$mockdir/output"
grep -q 'PASS: original EGRESS deny-all' "$mockdir/output"
grep -q 'PASS: no public direct roles/run.invoker' "$mockdir/output"
if grep -E '(^| )(create|delete|update|patch|add-iam-policy-binding|remove-iam-policy-binding)( |$)' "$CALLS_FILE"; then
  echo 'FAIL: inventory attempted a mutation' >&2; exit 1
fi
if ! grep -q -- '--project a2a-rails-test' "$CALLS_FILE"; then
  echo 'FAIL: missing explicitly scoped project' >&2; exit 1
fi
if MOCK_PUBLIC=1 bash "$script" --read-only > /dev/null 2>&1; then
  echo 'FAIL: public IAM binding not rejected' >&2; exit 1
fi
if MOCK_DENY_DISABLED=1 bash "$script" --read-only > /dev/null 2>&1; then
  echo 'FAIL: disabled firewall rule not rejected' >&2; exit 1
fi
echo 'PASS: read-only GCP inventory and fail-closed guards (4 cases)'
