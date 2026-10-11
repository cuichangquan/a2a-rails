#!/usr/bin/env bash
# Advisory only. Never skips required CI, changes deployment, or creates infrastructure.
set -euo pipefail

usage() {
  echo 'Usage: scripts/verification/plan.sh --files PATH [PATH ...]' >&2
  echo '       git diff --name-only BASE...HEAD | xargs -r scripts/verification/plan.sh --files' >&2
  exit 2
}

[[ "${1:-}" == "--files" ]] || usage
shift
(( $# > 0 )) || usage

level=0
reasons=()
raise() {
  local candidate="$1" message="$2"
  if (( candidate > level )); then level="$candidate"; fi
  reasons+=("$message")
}

for path in "$@"; do
  [[ -n "$path" && "$path" != /* && "$path" != *'..'* ]] || { echo "Invalid path" >&2; exit 2; }
  case "$path" in
    lib/a2a/rails/client/outbound_policy.rb|lib/a2a/rails/client/pinned_https_transport.rb|lib/a2a/rails/client/agent_card_resolver.rb|lib/a2a/rails/authentication.rb|lib/a2a/rails/request_guard.rb|.github/workflows/a2a-outbound-public-egress.yml)
      raise 3 "Security/egress-sensitive: $path" ;;
    lib/*|app/*|config/*|test/*|spikes/*|Gemfile|a2a-rails.gemspec|Rakefile|.github/workflows/*)
      raise 2 "Runtime, tests, dependencies or CI: $path" ;;
    scripts/verification/*|scripts/gcp-test/*)
      raise 1 "Validation tooling: $path" ;;
    docs/*|README.md|CHANGELOG.md|ROADMAP.md|SECURITY.md|LICENSE|.gitignore)
      reasons+=("Documentation or metadata: $path") ;;
    *) raise 2 "Unknown change (conservative): $path" ;;
  esac
done

case "$level" in
  0) echo 'Recommendation: DOCS-ONLY — review links/content and run the lightweight docs/tooling checks.' ;;
  1) echo 'Recommendation: LEVEL 1 — run offline script tests and any documentation checks.' ;;
  2) echo 'Recommendation: LEVEL 2 — run offline tests and relevant installed-Gem, Rails/SDK integration CI.' ;;
  3) echo 'Recommendation: LEVEL 3 REVIEW — run Level 2 security negatives and manually assess whether approved GCP public-HTTPS evidence is necessary.' ;;
esac
printf '  - %s\n' "${reasons[@]}"
echo 'Policy: advisory only; existing mandatory branch checks and release gates always take precedence.'
echo 'Policy: NEVER provision GCP or enable public/no-auth Cloud Run based on this output.'
