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
| Direct SendMessage | CI | CI | Official SDK actually returned Message, correct role/text |
| Rich direct Message | CI | CI | Native SDK text, structured Data, raw bytes, URL File; preserve opaque nested Data, base64, no remote file fetch |
| Task + Artifact | CI | CI | SDK-owned Task reaches COMPLETED with actual Artifact text/Data/raw and GetTask roundtrip |
| Nonterminal state | CI | CI | SDK-owned Task transitions to INPUT_REQUIRED, retrievable via GetTask |
| CancelTask | CI or **CAPABILITY-GAP** | CI or **CAPABILITY-GAP** | Server switches parked task to CANCELED; otherwise print SDK numeric remote error code |
| ListTasks pagination | CI or **CAPABILITY-GAP** | CI or **CAPABILITY-GAP** | Request page_size 1, obtain non-empty cursor and distinct second page; unsupported SDK RPC must be explicit |
| Missing GetTask | CI | CI | Numeric typed remote error code, nil Ruby exception cause and no untrusted error string |

**Reporting semantics:** `PASS` only on a successful operation with checked
protocol outputs. For CancelTask/ListTasks, an SDK-reported JSON-RPC
`RemoteError` is recorded as `CAPABILITY-GAP: UNSUPPORTED(code=N)`; this
is **not** proof of feature support and does not satisfy the release acceptance
gate. Malformed JSON, bad response types, wrong status, cursor absent with
multiple Tasks, unsafe TLS/origin behavior, or any other unexpected error
**fails the CI matrix** rather than being swallowed.

All results must be read from the actual two-job GitHub Actions matrix;
this design section is not a claim of PASS until those jobs finish.

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
