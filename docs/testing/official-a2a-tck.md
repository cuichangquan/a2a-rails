# Official A2A TCK — JSON-RPC MUST baseline (Step 17)

> **Scope: exploratory interoperability evidence, not a conformance certificate.**
>
> The current Gem is server-first, synchronous and non-streaming. This baseline checks **only JSON-RPC MUST-level** requirements using the *unreleased main branch*. It does **not** verify streaming, gRPC, HTTP+JSON, push notifications, authenticated public production, or all optional/SHOULD/MAY requirements. The public RubyGems 0.1.0 artifact has **not** been re-published and must not be exposed to untrusted clients.

## Official source / pinned revision

| Item | Value |
| --- | --- |
| Suite | [A2A Protocol Technology Compatibility Kit (TCK)](https://github.com/a2aproject/a2a-tck) |
| Revision | `263b9cfaf16a554bdfb166a7ba5b67716e946349` |
| Transport | `jsonrpc` only, as declared by the Agent Card |
| Level | `must` (RFC 2119 mandatory requirements only) |
| SUT | `test/support/tck_sut_server.rb`, a real Rails Engine using the local Gem source |
| Test origin | Bound to `127.0.0.1:9999`, `RAILS_ENV=test`, **no Internet access to the SUT** |
| Test runner | Python 3.11+, `uv` |
| CI | [Official A2A TCK baseline workflow](../../.github/workflows/official-a2a-tck.yml) |

The official runner uses `--sut-host`, `--transport`, `--level` (not the outdated `--sut-url`/`--category` arguments shown in some older upstream guides).

## Reproduce locally

On a Ruby 3.3+ / Rails 8-compatible development machine, from **the a2a-rails repository root**:

```bash
bundle install
RAILS_ENV=test RACK_ENV=test bundle exec ruby test/support/tck_sut_server.rb
```

In a second terminal:

```bash
git clone https://github.com/a2aproject/a2a-tck.git /tmp/a2a-tck
cd /tmp/a2a-tck
git checkout 263b9cfaf16a554bdfb166a7ba5b67716e946349
uv sync
uv run python run_tck.py \
  --sut-host http://127.0.0.1:9999 \
  --transport jsonrpc \
  --level must
```

Run these commands only on a trusted local development machine. **Never change the server bind address to `0.0.0.0`** to make it accessible from an external machine. The test SUT deliberately relies on the local Rails `test` environment's anonymous Quick Start fallback. Published public deployments must use a real host verifier and matching Agent Card security requirements.

In the TCK checkout, inspect:

- `reports/compatibility.json` — per-requirement results and per-transport totals.
- `reports/compatibility.html` — rendered compatibility analysis.
- `reports/junitreport.xml` and `reports/tck_report.html` — pytest results.

The GitHub Actions job attaches all reports and SUT/runner logs as **`a2a-tck-jsonrpc-must-baseline`** (14-day artifact retention).

## Test result interpretation

The GitHub Actions TCK *runner step* uses `continue-on-error: true` **intentionally**: until results are triaged, a failing conformance test does not block other Ruby/Rails checks. Consequently, a **green workflow does not mean TCK PASS**.

Keep these categories separate when reviewing the report:

| Result | Meaning |
| --- | --- |
| PASS | A specifically exercised requirement passed for this SUT/revision. |
| FAIL | A tested requirement failed or test setup was not compatible — investigate and fix if genuine. |
| SKIP | Requirement/transport not executed; **not a pass**. |
| NOT TESTED | Missing coverage; **not a pass**. |
| Unsupported | Not implemented and not advertised by the Gem (e.g. SSE, HTTP+JSON, gRPC, push). Do not silently count as passing. |

The TCK may exercise behavior outside v0.1's intentionally minimal server feature set, especially asynchronous/in-progress task flows. Distinguish mandatory protocol violations from valid capability-dependent skips with evidence; do not weaken production authentication or falsify the Agent Card solely to improve a score.

## Baseline evidence

- **CI run:** [PR #20 / official TCK workflow](https://github.com/cuichangquan/a2a-rails/pull/20).
- Actual results and failure classification will be recorded after reviewing the reports; there is **no claim of full conformance** here.
- Official Ruby/Rails regression CI is separate from the TCK baseline.
- Tracking: [Issue #19](https://github.com/cuichangquan/a2a-rails/issues/19); [ROADMAP.md](../../ROADMAP.md).

## Next actions

1. Confirm the pinned test server starts and the official CLI writes complete reports.
2. Review actual MUST-level JSON-RPC passes/failures/skips and identify the high-value compatibility defects.
3. Apply narrow fixes with regression tests (without weakening production security).
4. Re-run the official TCK on the same pinned revision and record before/after evidence.
5. Follow with independent Python/Go client interoperability and protocol coverage expansion.
