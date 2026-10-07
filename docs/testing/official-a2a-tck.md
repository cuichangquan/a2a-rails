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

## Step 17-1: real TCK rerun after focused error fixes

[PR #21](https://github.com/cuichangquan/a2a-rails/pull/21) changes only the confirmed error cases: unsupported push config methods now emit the defined `PushNotificationNotSupportedError (-32003)`; unsupported HTTP `Content-Type` / `Content-Encoding` now returns an empty HTTP `415` response rather than a JSON body that resembles an invalid JSON-RPC envelope.

**Pinned official rerun:** [GitHub Actions #37572266638](https://github.com/cuichangquan/a2a-rails/actions/runs/37572266638), [complete report artifact](https://github.com/cuichangquan/a2a-rails/actions/runs/37572266638/artifacts/11461287525). Results are measured from this run, not an extrapolation:

| Metric | Initial Puma baseline (#37571735872) | After PR #21 (#37572266638) |
| --- | ---: | ---: |
| pytest passed | 56 | **58** |
| pytest failed | 9 | **6** |
| pytest skipped | 170 | **171** |
| pytest deselected | 30 | 30 |
| JSON-RPC requirement results: pass | 54 | **56** |
| JSON-RPC requirement results: fail | 9 | **6** |
| JSON-RPC requirement results: skip | 27 | 27 |
| TCK-reported MUST compatibility (full suite denominator) | 64.0% | **66.7%** |

The three reduced failures are **two fixed push-notification error mappings** and **one HTTP 415 case now accepted as an HTTP-level rejection and skipped**. The latter is **not** a newly supported A2A operation.

### Remaining six pytest failures

- **4 × `DM-ART-001`:** Fixture-generated Artifacts do not match TCK canned text/file/file-URL/data examples. Add an intentional test Agent output strategy and verify real Gem mapping.
- **1 × `DM-MSG-001`:** SUT always returns Task; special TCK scenario requests a direct Message. Investigate supported result types before changing the Gem API.
- **1 × `CORE-SEND-003`:** The pinned TCK registry does not declare `expected_error` despite the requirement explicitly demanding `ContentTypeNotSupportedError`. The server correctly returns `-32005` for unsupported content. Verify with upstream and do not incorrectly return success to satisfy the test.

**Important:** 6 pytest failures remain and this baseline is **not a conformant/certified A2A implementation**. Informational GitHub Actions green reflects job infrastructure, not a passing TCK.

## Next actions

1. Extend a *test-only*, reproducible SUT to cover supported file/data Artifact cases, with ordinary Gem-level regression tests.
2. Investigate A2A Message-vs-Task response union for the direct-Message TCK case without changing server behavior solely for a canned test.
3. Investigate/report the upstream TCK `CORE-SEND-003` expected-error registry inconsistency.
4. Re-run the pinned TCK and document the true remaining pass/fail/skip counts.
5. Follow with official Python/Go client interoperability and protocol coverage expansion.

## Step 17-2: verify existing Text/Data Artifact mapping with official fixtures

[PR #22](https://github.com/cuichangquan/a2a-rails/pull/22) adapts only the **local test SUT** to return deterministic outputs for the official TCK's session-unique `tck-artifact-text-` and `tck-artifact-data-` message IDs. The Gem's ordinary `ArtifactMapper` maps a String to a TextPart and a Hash to a DataPart; there are **no special wire responses or production behavior changes**.

**Official pinned rerun:** [GitHub Actions #37572722890](https://github.com/cuichangquan/a2a-rails/actions/runs/37572722890), TCK `263b9cfaf16a554bdfb166a7ba5b67716e946349`, JSON-RPC MUST only.

| Measurement | After Step 17-1 | After Step 17-2 |
| --- | ---: | ---: |
| pytest passed | 58 | **60** |
| pytest failed | 6 | **4** |
| pytest skipped | 171 | 171 |
| pytest deselected | 30 | 30 |
| JSON-RPC requirement observations passed | 56 | **58** |
| JSON-RPC requirement observations failed | 6 | **4** |
| JSON-RPC skipped | 27 | 27 |
| Agent Card observations passed | 6 | 6 |
| Overall TCK-reported MUST compatibility | 66.7% | **66.7%** |

The aggregate percentage remains unchanged because the `DM-ART-001` requirement is *still* marked FAIL while its file-related test cases fail. This is not a conformance pass.

### Remaining four pytest failures

1. **Two file Artifact cases (`DM-ART-001`).** Current `Task::ArtifactMapper` / `Protocol::TaskMapper` support Handler outputs as text or structured data, not outbound A2A file bytes/URLs with `filename`/`mediaType`. Implement genuine file output mapping, schema validation and tests in a separate feature PR; do **not** fabricate a FilePart in the test SUT.
2. **One direct-Message case (`DM-MSG-001`).** This minimal server always returns a Task from SendMessage. The protocol permits a Task-or-Message result; the pinned TCK requires a special fixture `Direct message response`. Evaluate adding opt-in Message results via the existing SDK before expanding the public Handler contract.
3. **One unsupported input-media case (`CORE-SEND-003`).** The Gem correctly rejects the unsupported media with `ContentTypeNotSupportedError (-32005)`. The pinned TCK definition of this requirement does not include `expected_error`, while its implementation interprets the error as unexpected. Treat as an upstream TCK registry mismatch, not a reason to accept unsupported media.

No assertion of full interoperability, production deployment safety, or published v0.1.0 feature changes is made. The TCK workflow is **informational**: inspect the actual reports, not its green badge.


## Step 17-3: real FilePart output via the Gem's Handler result API

[PR #23](https://github.com/cuichangquan/a2a-rails/pull/23) introduces a typed `A2A::Rails::FileArtifact` Handler result for inline raw bytes (Base64 on the wire) and HTTPS file references. The normal ArtifactMapper and SDK serialize `raw`/`url`, `filename`, and `mediaType`; the **test-only** Echo Agent uses the real API for the two official `tck-artifact-file-` and `tck-artifact-file-url-` scenarios.

- New API and safety constraints: [File Artifact guide](../guides/file-artifacts.md).
- Pinned official TCK rerun (initial feature implementation): [Actions #37573700959](https://github.com/cuichangquan/a2a-rails/actions/runs/37573700959), commit `c4dedfdb79613902bee34edf516be8ad8f80620e`. The final PR revision requires a full Ruby CI pass as well.
- TCK revision remains `263b9cfaf16a554bdfb166a7ba5b67716e946349` with `--transport jsonrpc --level must`.

| Measurement | Step 17-2 | Step 17-3 |
| --- | ---: | ---: |
| pytest passed | 60 | **62** |
| pytest failed | 4 | **2** |
| pytest skipped | 171 | 171 |
| pytest deselected | 30 | 30 |
| JSON-RPC requirement observations passed | 58 | **60** |
| JSON-RPC requirement observations failed | 4 | **2** |
| JSON-RPC skipped | 27 | 27 |
| Agent Card observations passed | 6 | 6 |
| TCK-reported MUST compatibility (full suite denominator) | 66.7% | **68.0%** |

**Only two pytest failures remain in this chosen JSON-RPC MUST profile:**

1. **`DM-MSG-001` — direct Message response**: The existing Gem deliberately creates completed Tasks for SendMessage; the TCK's particular fixture requests a Message result. Support must be designed separately without replacing currently supported Task-based semantics.
2. **`CORE-SEND-003` — upstream TCK expected-error binding**: the Gem rejects unsupported inbound file media with A2A `ContentTypeNotSupportedError (-32005)`, which is correct; the pinned upstream requirement specifies that behavior in prose but does not populate `expected_error`. This is an upstream test issue to track, not grounds to misreport or weaken validation.

**This does not mean 100% protocol conformance.** The TCK report aggregates other transport/capability requirements, and its runner step is deliberately informational; a green workflow is not a TCK pass. The change exists on unreleased source, not published RubyGems v0.1.0.
