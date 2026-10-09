# Step 29-5r — Private v0.3.0.rc1 build-once / installed-artifact verification

**Status:** candidate test infrastructure; **NOT a released or tagged RC**.  
**Baseline source:** latest `main` at start `8f5b5433942adac0b04274116cc46ad82aaf5fed` (Step 29-5q); the CI run records its own immutable **workflow checkout commit** in `SOURCE_COMMIT`.  
**Target artifact:** `a2a-rails-0.3.0.rc1.gem` / `SHA256SUMS` / `STAGING_DELTA` / `SOURCE_COMMIT` as **private GitHub Actions artifacts only**. No GitHub Release, tag, RubyGems publication, change to Cloud Run IAM or GCP spending.

## Why stage RC1 rather than bump VERSION on main now?

The already-published stable `a2a-rails 0.2.0` is immutable, and a legacy exact-stable artifact workflow still checks out the repository with the source `VERSION = "0.2.0"`. Changing source `VERSION` to RC1 on main during a preliminary test would break that stable 0.2.0 workflow and blur published-versus-unpublished provenance.

Instead [the dedicated CI workflow](../../.github/workflows/v0.3-client-private-candidate.yml) performs **one reproducible, explicit test-only transformation**:

1. `git archive` of the checked-out commit into an isolated staging directory.
2. Change only `lib/a2a/rails/version.rb` inside staging from `0.2.0` to `0.3.0.rc1`; the workspace and stable RubyGems package are untouched.
3. Run `gem build` **once** inside that stage, inspect the spec and extract files, confirm the installed Client/pinning/Engine code matches the Git source byte-for-byte, then compute `sha256sum` to `SHA256SUMS`. Record source SHA and exact staging delta.
4. Upload **one** private, run-scoped candidate artifact (14-day retention). **Every consumer job** downloads precisely that artifact, checks `sha256sum -c SHA256SUMS` plus the recorded checkout SHA *before* installation, and refuses to load a Gem from the workspace.

This proves a testable versioned Gem **byte identity within one CI run**, but **does not make the published RC1 source identical to a dedicated frozen RC1 Git commit**. If source files change or a new workflow run occurs, the SHA256 and artifact identity may differ. An independently reviewed, separately frozen release branch/commit, with its real `VERSION` set to the chosen release candidate, remains required for eventual publication approval. **Do not push the private CI bytes to RubyGems or attach them to a release without that governance.**

## Acceptance matrix

| Gate | Mechanism / requirement |
| --- | --- |
| One `0.3.0.rc1` build and SHA256 | `build-once`: isolated `git archive`, only VERSION-stage delta, `gem build` once, Gem::Package metadata + Client/Engine byte comparison; upload Gem + SHA256 + source commit |
| Installed Client-only Rails | 6 separate job hosts: Ruby 3.3/3.4/4.0 × Rails 8.0/8.1; install exact downloaded Gem and Rails in a clean bundle. Assert `VERSION`, exact non-checkout Gem path, Client class, client-only server routes HTTP 404 |
| Installed Server security regression | The same 6 installed bundles execute existing `test/support/production_security_http_smoke.rb` in `RAILS_ENV=production` (host auth, no accidental anonymous access); do not substitute source checkout |
| Real installed PostgreSQL integration | 4 independent clean Rails/PostgreSQL 16 instances: Rails 8.0/8.1 × default/acronym inflection, verify identical artifact SHA, migrations, HTTP auth, Task durability/restart, concurrency races and bounded pruning |
| Real external SDK HTTPS interop **from installed candidate** | 2 more jobs: independent official Python `a2a-sdk==1.2.2` and Go `a2a-go/v2@v2.6.0` native loopback HTTPS server. The existing Rails public Client probe loads the **installed** RC1 (not `-Ilib`), checks real Cards, rich Parts/Task state, Cancel, Python pagination, and Go authenticated tenant isolation/ListTasks |
| Source-level broad matrix | Existing `sdk-spike.yml` Gem/Ruby/Rails matrix remains a distinct run; its source-level results are **not** substituted for installed RC tests |

### Technical proof boundaries

- The CI agent, PostgreSQL and SDK servers use disposable GitHub-hosted machines, test-only CA and fixed fake bearer tokens. No public endpoint, real cloud resources or production identities are accessed.
- The HTTPS SDK probe continues to fail-closed under the **public Client constructor** and only uses a test-only internal loopback IP/CA seam for local certificates. The released constructor's SSRF/TLS restrictions are not relaxed.
- The installed matrix proves a subset of Client/PG/Server security behavior. It does not prove production workload sizing, real IdP validation, external exactly-once effects, universal third-party compatibility, multi-host task durability or compliance certification.
- An **independent security reviewer** must approve the frozen *actual* release candidate bytes and source revision, as well as a reviewed resolution of the separately unapproved public/no-auth Cloud Run test criterion. The owner must explicitly approve any tag, GitHub Release and RubyGems push.

## CI review ledger

Inspect the final-head [private candidate Actions workflow](https://github.com/cuichangquan/a2a-rails/actions/workflows/v0.3-client-private-candidate.yml) and its uploaded `SHA256SUMS` / `SOURCE_COMMIT`. Record the exact run ID and verified SHA256 separately in Issue #90 **after** the complete build + all 12 installed jobs finish. Do not claim CI success until every matrix job passes. The CI-produced package is temporary and is **not** preserved as a final official release candidate.

**Issue #90 stays OPEN; v0.3.x NO-GO; official stable RubyGems remains 0.2.0.**
