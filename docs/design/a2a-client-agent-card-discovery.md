# Step 29-3c — Safe Agent Card discovery & JSON-RPC routing

> Status: internal integration under review; **no public `A2A::Rails::Client` exists**. Stable published Gem remains **0.2.0**.
>
> Tracking: [Issue #82](https://github.com/cuichangquan/a2a-rails/issues/82), parent [Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75), security foundations [PR #79](https://github.com/cuichangquan/a2a-rails/pull/79) and [PR #81](https://github.com/cuichangquan/a2a-rails/pull/81).

## Internal boundary

The internal `A2A::Rails::Client::AgentCardResolver` wraps the existing
`OutboundPolicy` and `PinnedHttpsTransport`:

```text
Explicitly configured HTTPS Agent Card URL
                  |
       PinnedHttpsTransport
    (DNS/origin/IP/Host/SNI/TLS)
                  |
          A2A 1.0 Agent Card
                  |
   first JSONRPC protocolVersion=1.0
                  |
  independently validated interface.url
       (same allowlist + DNS pinning)
                  |
    JSONRPC POST A2A-Version: 1.0
        (pinned again at connect)
```

The code is **not** required by the Gem entrypoint; it is not a supported or
released Rails Client. Default construction uses actual HTTPS origin policy and
socket-pinning transport. Any injected policy/transport is an internal test
seam and must never become a publicly configurable bypass.

## Agent Card rules

- Fetch the **explicit** `agent_card_url` using `get_json`; never guess a
  Card URL from the RPC endpoint.
- Validate required identifying strings, capabilities, input/output modes,
  skills and a nonempty, bounded `supportedInterfaces[]` array.
- Walk the declared array in its original preference order and select the
  **first** `protocolBinding == "JSONRPC"` and `protocolVersion == "1.0"`.
  Skip unsupported bindings/versions; **no downgrade/fallback** when a matching
  URL fails outbound security checks.
- Revalidate the selected, untrusted interface URL against the same exact
  HTTPS-origin allowlist and approved public IPv4 DNS constraints.
- Return immutable discovery data and the selected URL; preserve unknown
  Agent Card fields without symbol conversion.
- Optional interface `tenant` is an opaque string, **including an empty
  string** if declared. It is placed in the `params.tenant` field on every
  supported RPC, not the JSON-RPC envelope. Reject caller-supplied `tenant`
  overrides; omit `tenant` entirely if the Card did not declare it.

## Authentication boundary and supported internal RPCs

- The Card receives **no credentials by default**. Only `card_authorization`
  and its exact matching `card_credential_origin` may authorize discovery.
- Separately, RPC requests may receive `authorization` and an exact
  `credential_origin`. Credentials are evaluated by the pinned transport
  only after origin/DNS validation; a Card callback is never reused as the
  RPC callback (or vice versa).
- Allowed internal JSON-RPC methods for this slice: `SendMessage`,
  `GetTask`, `ListTasks`, `CancelTask`. The future public facade will
  provide typed method inputs and normalized DTOs.
- Use `jsonrpc: "2.0"`, the caller's stable `id`, the exact method name,
  and A2A-Version `1.0` on POST. No SDK `Console.info` path is invoked.
- Reject malformed JSON-RPC envelopes, wrong IDs and ambiguous
  `result`/`error`; a remote A2A error retains its integer code but does
  **not** surface untrusted remote text/metadata in a Ruby exception.

## Tests / evidence

- [Unit tests](../../test/unit/client/agent_card_resolver_test.rb) cover
  v1.0 preference, absence of fallback, declared tenant propagation for
  every method, invalid Cards, missing fields, private DNS, untrusted
  interface origin, immutable response data and safe error handling.
- [Real local pinned HTTPS tests](../../test/integration/client/pinned_https_transport_test.rb)
  exercise Agent Card GET, a distinct pinned HTTPS JSON-RPC POST endpoint,
  exact paths, the v1 version header, distinct Card/RPC credentials,
  tenant round-trip, redirect denial and credential-origin failure.
- Local HTTPS tests intentionally inject a **test-only loopback policy** to
  connect to ephemeral OpenSSL servers. The real production OutboundPolicy
  rejects that same loopback address in its own tests.

## Remaining NO-GO items

- Full public `A2A::Rails::Client` facade/typed DTOs/inputs/errors,
  configuration and client-only Rails Engine boot behavior.
- Broader production deployment network policy evaluation, IPv6 support
  decisions and independent cross-language server tests of the **new**
  outbound transport.
- Agent Card signature verification policy, authenticated extended Cards,
  multi-origin token audience semantics and host-specific authorization.
- Structured safe logs under concurrency, comprehensive JSON-RPC fixtures,
  cancellation/timeout reconciliation, full protocol schema validation.
- Strict end-to-end release gates and published Gem verification.

**Next: Step 29-4 — typed outbound operations/DTOs and app API**, followed
by independent published server interoperability. Do not release the Client
until these prerequisites are tested and explicitly approved.
