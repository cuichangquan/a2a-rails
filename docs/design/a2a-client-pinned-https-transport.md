# Step 29-3b — Pinned-IP HTTPS Transport Security Boundary

> **Status:** internal implementation verified by the Ruby 3.3/3.4/4.0 SDK/Gem matrix ([first successful CI run](https://github.com/cuichangquan/a2a-rails/actions/runs/37752099516)), **not** the public `A2A::Rails::Client` and **not approved for production**.
> Tracking: [Issue #80](https://github.com/cuichangquan/a2a-rails/issues/80) and [Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75).

## Connection and trust model

Internal class: `A2A::Rails::Client::PinnedHttpsTransport`. This class is deliberately not required from `lib/a2a-rails.rb`; existing Rails Server APIs remain untouched.

`get_json(url:)` and `post_json(url:, json:)` are internal methods. The transport:

1. Revalidates the configured/requested URL with `OutboundPolicy#resolve!` **on each request**, covering exact origin and resolved public IPv4 only.
2. Calls `Net::HTTP.new(target.host, target.port, nil)` to disable the environment-proxy default.
3. Calls `http.ipaddr = target.addresses.first` **before connection**: the actual socket dials only the previously checked IP. No hostname DNS lookup is necessary in the HTTP stack; `http.ipaddr` is checked against the selected address after connect.
4. Sets `use_ssl = true`, `verify_mode = VERIFY_PEER`, `verify_hostname = true`. The HTTP hostname, TLS SNI and certificate verification use **target.host**, never the pinned numeric address.
5. Sends only a single HTTPS request per connection; no automatic retries (`max_retries = 0`) or HTTP redirects.
6. Sets connect/read/write timeouts plus an absolute total `Timeout.timeout` deadline. Caps request bytes, response bytes **while streaming**, and JSON nesting depth. Rejects non-JSON content types and compressed response bodies.
7. No generic outgoing custom headers, cookies, URLs with userinfo/query, verbose request/response logs, or proxy tunneling. `Authorization` is accepted via an application callback **only when the caller also provides the exact target `credential_origin`**. No credentials are evaluated for a rejected URL.
8. Parses successful `application/json` (or `application/a2a+json`) into a plain Ruby value. Does not interpret Task or direct Message, which belongs in the future Client protocol adapter.

The implementation intentionally supports **public IPv4 destinations only**. IPv6 is rejected until a dedicated reviewed path can preserve the same connect-time security guarantees.

## Tests and limitations

[Test code](../../test/integration/client/pinned_https_transport_test.rb) runs against an ephemeral local OpenSSL TLS server with a one-off test-only policy that supplies the loopback address **solely for the socket-pinning and TLS test**. A separate test uses the real `OutboundPolicy` and proves that loopback DNS is denied before any HTTP request. The test-only policy is never wired into a public initializer or the Gem entrypoint.

The real TLS tests cover:

- Pinned-IP success with original hostname certificate validation and verified path
- JSON-RPC POST with A2A version header and origin-bound test credential
- Reject cross-origin credential callback *before* evaluating it
- Deny actual loopback DNS via real production preflight
- Reject metadata IP redirects without following
- Reject an oversized JSON response (including streaming budget) and invalid JSON/content type
- Reject untrusted certificates and certificates valid only for another hostname
- Reject slow responses by configured deadline
- Return sanitized 403 error status without exposing its body
- Sanitize failed authorization callbacks without exposing the original exception/cause
- Enforce per-request size and option limits

CI: existing `sdk-spike.yml` runs all Minitest suites on Ruby 3.3, 3.4, and 4.0 and Rails 8.0/8.1. The first complete real-TLS suite run passed [Actions #37752099516](https://github.com/cuichangquan/a2a-rails/actions/runs/37752099516) (**Ruby 3.4: 227 tests, 994 assertions, zero failures/errors**), before a further credential-error hardening test was added. Verify the newer head SHA and report final matrix status before merge.

## Security properties **not yet proven**

- The transport is **internal only**; full Agent Card discovery and `supportedInterfaces[]` selection are not yet wired.
- The application must not pass a user-controlled URL without explicit approved origins. The adapter must make the real policy mandatory and prevent a caller from substituting the local test policy.
- A slow, non-cooperative network driver may interact with Ruby `Timeout.timeout` despite `Net::HTTP` per-I/O deadlines. Future load/timeout tests should validate concurrent Rails job behavior.
- Third-party SDK `Console.info` prints RPC request parameters. This internal `Net::HTTP` transport **does not invoke the SDK Client** and does not log payloads; eventual protocol adapter must preserve that boundary.
- JSON-RPC envelopes, Agent Card shape, HTTP status/error normalization, credentials per principal, and full public DTOs are **not yet implemented**.
- No audit evidence of independent public remote servers using the new outbound transport exists yet (local TLS tests only).
- IPv6/TLS platform variation beyond CI matrix, bandwidth/rate limits, and production deployment network egress controls require additional review.

## Decision

Passing this suite can justify merging an **internal foundation** only. It does **not** authorize release of `A2A::Rails::Client`, a new version, or production deployment. The next small slice is **Step 29-3c: safe Agent Card discovery, interface selection and transport integration**, plus negative JSONRPC and credential tests.
