# Step 26-1 — Published rc2 Gem in a PostgreSQL-backed Rails host

Date: **2026-10-08**  
Tracking: [Step 26 #62](https://github.com/cuichangquan/a2a-rails/issues/62) · [Published-Gem host smoke PR #64](https://github.com/cuichangquan/a2a-rails/pull/64) · [Zeitwerk/migration blocker #65](https://github.com/cuichangquan/a2a-rails/issues/65)

## Verification result and narrow scope

| Installed version | Rails host | PostgreSQL | Result |
| --- | --- | --- | --- |
| Published `a2a-rails 0.2.0.rc2` | Rails 8.0.x, Ruby 3.4.10 | PostgreSQL 16 | **PASS WITH DOCUMENTED HOST WORKAROUNDS** |
| Published `a2a-rails 0.2.0.rc2` | Rails 8.1.x, Ruby 3.4.10 | PostgreSQL 16 | **PASS WITH DOCUMENTED HOST WORKAROUNDS** |

**CI evidence:** [Published rc2 PostgreSQL host smoke #37713804918](https://github.com/cuichangquan/a2a-rails/actions/runs/37713804918), both matrix jobs success. Source regression CI [#37713804924](https://github.com/cuichangquan/a2a-rails/actions/runs/37713804924), success.

The workflow:
1. Downloads `0.2.0.rc2` **from RubyGems.org**, validates SHA256 `d65fdd65003987ece96f0a90a4cf28563929be99d26658deeb275fca30c5d694`, then installs it. It never substitutes the local checkout for the installed Gem.
2. Generates **fresh Rails 8.0/8.1 PostgreSQL hosts**, runs the *packaged* `a2a:rails:task_store` generator and `bin/rails db:migrate`.
3. Boots the Rails application with `RAILS_ENV=production` and explicitly configured `task_store = :active_record` and **test-only** Bearer identities.
4. Exercises A2A Agent Card, SendMessage, GetTask, ListTasks, signed pagination cursors, tenant read/list/cancel denial, and rightful CancelTask using Rails' Rack HTTP request boundary.
5. Reboots a fresh Rails process against the same PostgreSQL DB, verifies stored Task state and signed cursor continuity, and executes two independent Rails processes racing a terminal transition.
6. Tests 1-hour terminal retention, aggregate stats, artificial expiry of exactly two Tasks, **one-row / one-batch prune bound**, final cleanup, and preservation of non-expired foreign Tasks.

## Critical finding — rc2 is NOT clean production-boot ready

The **unmodified published rc2** failed in a clean production Rails host:

- Default Zeitwerk eager loading expects `A2a::Rails::AgentCardsController` for Gem controller paths even though the class is `A2A::Rails::AgentCardsController`.
- Registering the `A2A` acronym fixes controller resolution, **but** changes the inferred migration class to `CreateA2ARailsTasks`, while rc2's template emits `CreateA2aRailsTasks`.

For narrow database behavior testing, the disposable test host includes **two explicit workarounds**:

- Register the `A2A` acronym in the host's inflections before Rails boot.
- Rename the generated migration class inside the temporary host to match that host inflection.

These are **not published Gem changes**, and the green CI **must not** be used to claim an out-of-the-box production-boot/migration pass. Both defects require a Gem-side fix and another **new exact-artifact** installed-host verification before stable `0.2.0` is approved. See [#65](https://github.com/cuichangquan/a2a-rails/issues/65).

## Reproduction

CI source: [workflow](../../.github/workflows/published-gem-postgres.yml) and [test harness](../../spikes/published_gem_postgres/smoke.rb).

Use a disposable PostgreSQL 16 database with a local test-only username/password and an isolated runner. On a Ruby 3.4.10 host with Rails 8.0.x or 8.1.x:

```bash
export TARGET_RAILS='~> 8.1.0'
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/a2a_rails_test'
export RAILS_ENV=production RACK_ENV=production
export SECRET_KEY_BASE='step-26-1-isolated-ci-host-secret-key-base-not-for-production'
export A2A_RAILS_SOURCE_ROOT="$PWD"

cd "$(mktemp -d)"
gem fetch a2a-rails -v 0.2.0.rc2 --clear-sources --source https://rubygems.org
echo 'd65fdd65003987ece96f0a90a4cf28563929be99d26658deeb275fca30c5d694  a2a-rails-0.2.0.rc2.gem' | sha256sum -c -
gem install --no-document ./a2a-rails-0.2.0.rc2.gem
gem install --no-document rails -v "$TARGET_RAILS"
# From a checked-out repository working directory, run:
# ruby spikes/published_gem_postgres/smoke.rb
```

The CI workflow is the canonical fully reproducible reference; the above commands show the artifact-fetch stage, not an end-to-end copy/paste script. Running the harness requires `PUBLISHED_GEM_FILE` and the checkout path.

## What remains unproven

- **No clean host without inflection/migration fixes:** Issue #65 blocks stable release until fixed and retested.
- No real issuer/audience/signature/revocation enforcement, business authorization or public-ingress controls; host test tokens are fixtures only.
- No real deployed reverse proxy/TLS, distributed rate limits, backups/PITR, DB capacity planning or incident recovery.
- The cross-process test proves shared PostgreSQL Task state and locking in **Rails runner processes with Rack HTTP requests**, not a networked Puma/worker/queue deployment; real async failure/recovery verification remains Step 26-3.
- **Issue #11 stays OPEN:** green installed-artifact durability tests do not authorize open public production.

Next work: fix [#65](https://github.com/cuichangquan/a2a-rails/issues/65) in the Gem with clean production host regression coverage; only then close the remaining A1 release gate in [Step 26 matrix](../release/v0.2.0-stable-readiness.md).