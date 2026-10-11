#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
plan="scripts/verification/plan.sh"
assert_contains() {
  local expected="$1"; shift
  local output
  output="$(bash "$plan" --files "$@")"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'FAIL: expected %s, got:\n%s\n' "$expected" "$output" >&2
    exit 1
  fi
}
assert_contains 'DOCS-ONLY' README.md docs/guides/outbound-a2a-client.md
assert_contains 'LEVEL 1' scripts/verification/plan.sh
assert_contains 'LEVEL 2' lib/a2a/rails/client.rb
assert_contains 'LEVEL 2' .github/workflows/a2a-client-contract.yml
assert_contains 'LEVEL 2' strange-new-file.txt
assert_contains 'LEVEL 3 REVIEW' lib/a2a/rails/client/outbound_policy.rb README.md
assert_contains 'LEVEL 3 REVIEW' .github/workflows/a2a-outbound-public-egress.yml
if bash "$plan" --files >/dev/null 2>&1; then echo 'FAIL: empty file list accepted' >&2; exit 1; fi
if bash "$plan" --files ../outside >/dev/null 2>&1; then echo 'FAIL: unsafe path accepted' >&2; exit 1; fi
if bash "$plan" --files /tmp/outside >/dev/null 2>&1; then echo 'FAIL: absolute path accepted' >&2; exit 1; fi
echo 'PASS: cost-aware validation plan regression (9 cases)'
