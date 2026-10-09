# Step 29-5n — Advanced independent official Python/Go A2A server interoperability

> **Scope:** unreleased outbound Rails Client only. Native loopback HTTPS test
> against **unmodified official SDK request handlers and Agent Cards** — no
> patched protocol JSON, Rails-shaped echo fixtures, public GCP resources or
> production credentials. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90)
> and [Step 29-5k release-gate audit](step-29-5k-client-release-gates-audit.md).
> **Stable RubyGems 0.2.0 unchanged. v0.3.x NO-GO.**

## Setup / independently controlled implementations

| Runtime | Official SDK pinned | Server handler | TLS and exposed origin |
| --- | --- | --- | --- |
| Python 3.12 | `a2a-sdk==1.2.2` | `DefaultRequestHandler`, `InMemoryTaskStore` | Native Uvicorn TLS on **127.0.0.1:3444**; Card advertises `https://python-agent.test:3444/python/a2a/jsonrpc` |
| Go 1.26 | `a2a-go/v2@v2.6.0` | `a2asrv.NewHandler`, JSONRPC handler's built-in store | Native Go `ListenAndServeTLS` on **127.0.0.1:3445**; Card advertises `https://go-agent.test:3445/go/agent/jsonrpc` |

The Rails public Client constructor is first exercised unchanged and
**required to reject** the synthetic test hostname/loopback target. Only
then does CI inject its old internal test-only loopback pin and locally trusted
ephemeral TLS certificate; production SSRF/DNS and TLS restrictions are not
weakened. The actual TLS peer, SNI/hostname, original Card, and SDK JSON-RPC
handlers are used throughout.

## Matrix and pass criterion

| Protocol dimension | Python | Go | Meaning of PASS |
| --- | --- | --- | --- |
| Direct SendMessage | **PASS** | **PASS** | Official SDK actually returned Message, correct role/text |
| Rich direct Message | **PASS** | **PASS** | Native SDK text, structured Data, raw bytes, URL File; preserve opaque nested Data, base64, no remote file fetch |
| Task + Artifact | **PASS** | **PASS** | SDK-owned Task reaches COMPLETED with actual Artifact text/Data/raw and GetTask roundtrip |
| Nonterminal state | **PASS** | **PASS** | SDK-owned Task transitions to INPUT_REQUIRED, retrievable via GetTask |
| CancelTask | **PASS** | **PASS** | Server switches parked task to CANCELED, GetTask observes transition |
| ListTasks pagination | **PASS** | **AUTH_REQUIRED (-31401)** | Python: page_size 1, nonempty cursor, distinct second page. Go: SDK refuses anonymous listing before pagination can be assessed; do **not** claim unsupported operation or PASS. |
| Missing GetTask | **PASS** | **PASS** | Numeric typed remote error code, nil Ruby exception cause and no untrusted error string |

**Reporting semantics:** `PASS` only on a successful operation with checked
protocol outputs. For CancelTask/ListTasks, an SDK-reported JSON-RPC `RemoteError`
is recorded as a `CAPABILITY-GAP`, **classified by code**. `-31401`
means the SDK refuses unauthenticated access; `-31403` means forbidden.
Known unsupported operation codes (`-32601` / `-32004`) are separately
classified `UNSUPPORTED`. All other codes are marked `REMOTE_ERROR_UNVERIFIED`,
never assumed to mean "unsupported". These classifications do **not**
prove successful execution. Malformed JSON, bad response types, wrong
status, a missing pagination cursor with multiple Tasks, unsafe TLS/origin
behavior, or any other unexpected error **fails CI** rather than being swallowed.

**Evidence from native SDK CI:** the Python job demonstrated every row,
including real `ListTasks` pagination. The Go job demonstrated all rows
except ListTasks pagination, whose anonymous request is rejected by the
official SDK with `-31401` (unauthenticated). This is an **authorization
scope constraint**, not a verified missing method. A follow-up with a
specifically authorized caller/SDK authentication policy is needed before
claiming Go ListTasks interop. The final PR-head CI run is the source
of truth for overall pass status.

## Files and reproducibility

- [GitHub Actions native HTTPS matrix](../../.github/workflows/a2a-outbound-official-servers.yml)
- [Python test-only executor](../../spikes/a2a_client_v03/python_sdk_https_server.py)
- [Go test-only executor](../../spikes/a2a_client_v03/go_sdk_https_server/main.go)
- [Ruby public-Client native HTTPS probe](../../spikes/a2a_client_v03/official_sdk_native_https_probe.rb)
- [Earlier 29-5b evidence](a2a-outbound-official-sdk-servers.md)

## Remaining release boundaries

This tests ephemeral **SDK in-memory stores**, not persistent multi-host
tasks or production scaling. Cross-origin authentication, proxy/CA/SSRF
adversarial gate, and log-sink secrecy are tracked separately. No streaming
or gRPC semantics, real OAuth security, large-file URL fetching, public/no-auth
Cloud Run experiment or multi-process queued Rails worker is tested here.
Feature gaps reported as unsupported remain work items or documented release
criteria decisions. Step **29-5o** queued Rails jobs and Step **29-5p**
independent release review still remain. No version tagging or RubyGems push.

**Issue #90 OPEN; v0.3.x NO-GO.**
