# Step 29-5b: outbound Client → official Python and Go A2A Server verification

**Status: test integration under review, not production approval or a Gem release.**

This test is intentionally the **opposite direction** of the existing Python/Go
client → Rails Server interoperability workflow.

## Servers and protocol

- Python server: official `a2a-sdk==1.2.2`, `DefaultRequestHandler`,
  `InMemoryTaskStore`, Starlette `create_agent_card_routes` and
  `create_jsonrpc_routes`, Uvicorn's **native HTTPS** port `3444`.
- Go server: official `github.com/a2aproject/a2a-go/v2@v2.6.0`,
  `a2asrv.NewHandler`, `NewJSONRPCHandler`, and
  `NewStaticAgentCardHandler`, Go `http.Server.ListenAndServeTLS` port
  `3445`.
- Both servers are independent SDK-language processes: **neither imports,
  loads, nor embeds the Rails Gem or its JSON-RPC server**.
- The **original, unmodified** Agent Card is served on
  `/.well-known/agent-card.json`. It advertises its true native HTTPS
  JSONRPC endpoint under `supportedInterfaces[]`. The Python and Go
  endpoints deliberately differ from `/a2a` to detect guessed paths.

## Safety and limits

CI binds each official server to **127.0.0.1 only** and generates one
ephemeral hostname certificate per job. `curl --resolve` verifies the
actual original Card and strict TLS certificate; Rails Client's
`PinnedHttpsTransport` then connects to the same TLS socket and verifies
the selected host via SNI and TLS peer certificate validation.

The public Rails Client constructor is exercised **as-is** to prove it
refuses the synthetic loopback-only test DNS target. Only after this
negative proof does the test inject a TEST-ONLY internal policy that
continues to validate the exact HTTPS origin while pinning to the local
loopback IP and uses a test CA. The **public Client API has no such
injection parameter**.

The direct Message codepath is exercised against **both** independent
SDK server implementations, and Python additionally tests completed
Task, Artifact and GetTask round trips. Production policy, IP blocklists,
and TLS verification are unchanged.

## Step 29-5n advanced interoperability matrix

The same **independent official** Python (`a2a-sdk==1.2.2`) and Go
(`a2a-go/v2@v2.6.0`) servers now supply richer, SDK-created protocol
responses to the unmodified Rails Client API (with **only** the existing
test-only local TLS policy/CA injection). The probe validates:

- Rich direct Message with SDK-generated **text + structured Data + raw File +
  URL File** Parts; preserved nested camelCase Data keys, base64 File data,
  immutable output and **no fetching** of returned URLs.
- Native Task containing SDK-generated Artifact **text/Data/raw** Parts, Task
  completion, stored Task/GetTask roundtrip.
- `TASK_STATE_INPUT_REQUIRED` returned by the server and subsequently
  retrieved by GetTask. CancelTask should transition the parked Task to
  CANCELED, and GetTask must reflect the transition **when supported**.
- ListTasks `page_size: 1` and `nextPageToken` fetching a **distinct second
  page**. Python SDK: PASS; Go SDK rejects unauthenticated listing with
  **`-31401`**, so Go pagination remains **NOT VERIFIED**.
- Nonexistent GetTask must be a **typed, sanitized remote JSON-RPC error**.

**Reporting rule:** only `PASS` means the end-to-end SDK operation truly
worked. An SDK-generated error on CancelTask or ListTasks is shown as a
`CAPABILITY-GAP` with its actual error-code classification: authentication
required (`-31401`) is **not** mislabeled as an unsupported operation.
A wrong response shape, unsupported Rails transformation, missing pagination
cursor despite multiple Tasks, invalid security behavior, or other unexpected
exception **fails CI**. The test does not monkey-patch SDK server
handlers or replace their responses with synthetic JSON.

The [SDK capability/evidence matrix](step-29-5n-official-sdk-advanced-matrix.md)
summarizes precise results and unresolved items.

## Still not demonstrated

- No public egress URL with unmodified DNS and unmodified Client
  initialization, as CI intentionally runs only local loopback servers.
- Production certificate authority, Cloud/Kubernetes egress and proxy
  configurations, formal security review and public endpoint authentication.
- Go Task persistence, ListTasks/CancelTask cross-language semantics, input
  required / auth required states, multi-origin credentials, backpressure and
  repeated requests under concurrent Rails jobs.
- Full protocol conformance certification, production deployment permission,
  or release of a new RubyGems version.

## Evidence

- [CI workflow](../../.github/workflows/a2a-outbound-official-servers.yml)
- [Python official A2A Server](../../spikes/a2a_client_v03/python_sdk_https_server.py)
- [Go official A2A Server](../../spikes/a2a_client_v03/go_sdk_https_server/main.go)
- [Rails outbound Client probe](../../spikes/a2a_client_v03/official_sdk_native_https_probe.rb)
- [Step 29-5 tracking #87](https://github.com/cuichangquan/a2a-rails/issues/87)

Published Gem stays at **0.2.0** until separate independent release approval.
