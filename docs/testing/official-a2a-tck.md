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

## Baseline evidence (2026-10-07)

- **Verified upstream TCK run:** [GitHub Actions #37571735872](https://github.com/cuichangquan/a2a-rails/actions/runs/37571735872).
- **Reports:** [download compatibility JSON, HTML, JUnit and server logs](https://github.com/cuichangquan/a2a-rails/actions/runs/37571735872/artifacts/11461346352) (artifact retention: 14 days).
- **SUT:** Puma on `127.0.0.1:9999` using current source, not the released v0.1.0 Gem.
- **Official pytest outcome:** **56 passed, 9 failed, 170 skipped, 30 deselected**. The job intentionally preserves the failure in the report while allowing the workflow to finish.
- **TCK-reported MUST compatibility:** **64.0%**. The denominator includes requirements outside this specific transport/profile, so **do not** interpret this as 64% of JSON-RPC operations passing.
- **JSON-RPC requirement breakdown:** **54 passed / 9 failed / 27 skipped** (90 recorded transport results).
- **Agent Card:** **6 passed / 0 failed**. gRPC and HTTP+JSON were not exercised as usable transport bindings.

### Failure classification (9 pytest failures)

| Area | Observed issue | Assessment |
| --- | --- | --- |
| Artifact content — 4 cases | The Echo fixture returns text, but the TCK requests canned text, file, file-URL and structured-data outputs. | **Fixture behavior / coverage gap:** not proof that all such Artifacts are impossible. Validate the Gem's supported artifact mapping separately. |
| Message response — 1 case | The fixture always returns a Task; TCK expects a Message response for its special scenario. | **Fixture/API coverage gap:** Task and Message are both allowed by the A2A SendMessage response union; assess a purpose-built SUT before calling this a protocol violation. |
| Push notification errors — 2 cases | Unsupported push methods return `UnsupportedOperationError (-32004)` instead of the more specific `PushNotificationNotSupportedError (-32003)`. | **Confirmed protocol error-mapping defect.** Fix the adapter in a targeted follow-up with regression tests. |
| Unsupported input media — 1 case | `CORE-SEND-003` describes an expected `ContentTypeNotSupportedError`, but the pinned TCK registry does not set `expected_error`, causing the parameterized test to treat an appropriate error as a failure. | **TCK requirement/test mismatch to investigate:** the Gem emits `-32005`; don't hide this or change it to success. |
| HTTP Content-Type error — 1 case | Wrong `Content-Type` currently returns HTTP 415 with a JSON `{"error":"..."}` body, which the TCK interprets as a malformed JSON-RPC error. | **HTTP boundary representation mismatch:** return an unambiguous non-JSON HTTP 415 or a valid JSON-RPC error envelope; keep authentication/body validation fail-closed. |

The **initial** WEBrick SUT run ([#37571366500](https://github.com/cuichangquan/a2a-rails/actions/runs/37571366500)) showed 51 pytest failures because its forward-only `rack.input` did not satisfy the Rails body parsing/replay expectations. **Do not use that run to assess protocol compliance.** The SUT was switched to Puma, and the valid POST endpoints were checked with direct HTTP requests before running the pinned TCK.

A clean **13-job Ruby/Rails regression CI** independently passed on the initial TCK integration commit: [#37571366462](https://github.com/cuichangquan/a2a-rails/actions/runs/37571366462). The new TCK workflow itself is **informational/non-gating**, not a substitute for the regression suite.

## Next actions

1. Fix push-not-supported error mapping (`-32003`) and wrong Content-Type HTTP boundary representation, with narrow regression tests.
2. Extend the standalone TCK SUT to deliberately produce file/data artifacts and the expected response profile *only where the Gem supports them*; do not implement bogus protocol output to satisfy a test.
3. Investigate and, if appropriate, report the `CORE-SEND-003` upstream TCK expectation mismatch.
4. Re-run the pinned TCK and record the exact before/after delta and remaining failures.
5. Follow with independent Python/Go client interoperability and protocol coverage expansion.
