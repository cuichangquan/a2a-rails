# Step 18 — Cross-language A2A interoperability (official clients)

> Only an isolated source-based Rails test SUT on 127.0.0.1:9998.
> This harness tests the checked-out source candidate, not a published release. Do not expose this
> deliberately anonymous test SUT to public networks.

## Pinned clients

- Python: official [a2a-python](https://github.com/a2aproject/a2a-python) via PyPI **a2a-sdk==1.2.2** (Python 3.12).
- Go: official [a2a-go](https://github.com/a2aproject/a2a-go) **github.com/a2aproject/a2a-go/v2 v2.6.0** (Go 1.26.0).
- Rails: Ruby 3.4, source Gem, test environment, JSON-RPC A2A Protocol **1.0**.
- CI: [.github/workflows/cross-language-interop.yml](../../.github/workflows/cross-language-interop.yml).
- Rails SUT: [test/support/interop_sut_server.rb](../../test/support/interop_sut_server.rb).

These are independent **official client APIs**, not scripted hand-built JSON-RPC success requests. A raw HTTP check of unsupported A2A-Version 0.3 complements the SDK calls.

## Coverage (both languages)

1. Discover Agent Card and select JSONRPC v1.0.
2. SendMessage returns synchronous completed Task with a text Artifact.
3. GetTask and ListTasks by context, including Artifacts.
4. SendMessage can instead return a direct Message with ROLE_AGENT and TextPart.
5. Direct response creates no Task.
6. CancelTask on a completed Task yields the specified noncancelable error (-32002).
7. Reject unsupported A2A-Version 0.3 with -32009; the Go test also inspects real SDK 1.0 request headers.

## Continuation candidate coverage (Python only)

The existing Python 1.2.2 client also exercises synchronous INPUT_REQUIRED:

- Data request, agent question with a Data part, GetTask and ListTasks while waiting.
- Two answers, including an incomplete answer that asks again; taskId-only continuation
  preserves Task and context IDs and completes the aggregate fixture (3 / 35000).
- Every SendMessage requests `historyLength: 0`, while application-side retained
  input still supplies the original year/month. A later GetTask checks stored history.
- Question Data retains string keys (`messageId` and `message_id`), false, null,
  empty objects and nested arrays through real SDK serialization and decoding.
- Text question/answer and CancelTask during INPUT_REQUIRED.

The SUT uses the Gem-owned `InputRequired` result and ordinary Ruby inputs. The
Python client deliberately uses official SDK DTOs: the Ruby SDK-boundary rule does
not prohibit a separate interoperability client from using its own native API.
There are no automatic retries, nonstandard RPCs or capability declarations.

These are test definitions, not a claim that the current candidate passed. Record
exact source SHA, command and result in the candidate evidence after execution.
The existing Go checks remain baseline checks; Go continuation is not asserted.

Limits: cancellation of a still-working Task, SSE streaming, gRPC, HTTP+JSON, push notifications, authorization on a real production identity backend and task durability are **not** covered. Existing Ruby CI separately tests Task ownership. This is **not** an A2A conformance certification.

## Reproduce locally

Use Ruby 3.4, Python 3.12 and Go 1.26.0:

Run the Rails host from the repository root:

    bundle install
    RAILS_ENV=test RACK_ENV=test bundle exec ruby test/support/interop_sut_server.rb

From another shell, at the repository root, for Python:

    python3 -m pip install 'a2a-sdk==1.2.2'
    INTEROP_SUT_URL=http://127.0.0.1:9998 python3 test/interop/python_client.py

For Go:

    cd test/interop/go
    go mod tidy
    INTEROP_SUT_URL=http://127.0.0.1:9998 go run .

The test SUT binds **only** 127.0.0.1, refuses non-test Rails environments, and uses the test-only anonymous authentication fallback. It should never be used as a public application template.

## Evidence

**Verified and merged 2026-10-07** via [PR #27](https://github.com/cuichangquan/a2a-rails/pull/27) (main `c7956cec9d75f71ce0face76e770a2d553316663`). [Final official-client CI #37576849497](https://github.com/cuichangquan/a2a-rails/actions/runs/37576849497) succeeded with **15 Python checks PASS and 16 Go checks PASS**, including Task/direct Message decoding and actual Go SDK A2A-Version: 1.0 headers. Independent [final Ruby/Rails CI #37576849516](https://github.com/cuichangquan/a2a-rails/actions/runs/37576849516) completed **13/13** jobs.

Scope is limited to the declared JSON-RPC v1.0 functionality and this test-only Rails SUT. It does not establish protocol-wide conformance or approval for public production.

The pinned TCK still separately has one upstream false failure CORE-SEND-003, recorded in [a2a-tck #202](https://github.com/a2aproject/a2a-tck/issues/202). This smoke does not replace that test suite.
