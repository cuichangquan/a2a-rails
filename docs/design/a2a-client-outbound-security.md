# Step 29-3a — Outbound Agent Target Preflight Security

> Status: **partial implementation under review**, not a usable/public A2A Client.
> Tracking: [Step 29 Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75).
> Prerequisites: Steps 29-1/29-2 design and SDK compatibility evidence are merged; the stable released Gem remains **0.2.0**.

## What this slice does

Adds an **isolated internal** `A2A::Rails::Client::OutboundPolicy` class under
`lib/a2a/rails/client/`. It is not required by `lib/a2a-rails.rb` and is **not**
a released/public Client API.

- Requires explicit exact HTTPS origins (scheme/host/port), no wildcards.
- Requires an absolute HTTPS URL for discovery and every selected remote Agent
  interface, with no credentials, query or fragment.
- Rejects DNS targets with malformed/ambiguous names, URL escapes and dot segments.
- DNS-resolves permitted hosts and rejects all results if even one is non-public,
  unsupported or invalid.
- Blocks common reserved/private IPv4 networks including link-local cloud metadata,
  loopback, shared address space, documentation networks and multicast.
- **Temporarily rejects all IPv6**, to avoid assuming complete IPv6 and
  IPv4-mapped-address enforcement before a transport implementation exists.
- Returns an immutable `Target` carrying the exact `url`, `origin`, hostname,
  port and approved IPv4 addresses. Errors expose a safe category, not URL secrets.
- Unit tests inject a fake DNS resolver; no outbound requests or production credentials.

## Non-goal / critical security boundary

**Preflight DNS resolution is not sufficient SSRF protection.**

A vulnerable sequence is:

1. Preflight resolves an allowed hostname to a public IP.
2. Another HTTP library independently resolves that hostname later.
3. DNS changes and the library connects to a private/local/metadata IP.

The next transport slice (29-3b) **MUST** connect only to an approved pinned
IP from the preflight Target, keeping TLS verification/SNI/Host bound to the validated
hostname and repeating policy evaluation on every new connection. Never fall back to
ordinary hostname dial or trust preflight alone.

Additional **NO-GO** conditions before any public Client release:

- TLS certificate/hostname validation and full connect-time IP pinning
- Exact endpoint/origin recheck for Agent Card `supportedInterfaces[]`
- No redirects and no credentials forwarded across origin boundaries
- Proxy bypass/explicit proxy hardening and rebinding regression tests
- Bounded connect, read, total timeout, request/response bytes, JSON depth
- SDK `Console.info` payload logging disabled without unsafe process-global switches
- Typed errors, Task/direct Message data mapping and actual independent HTTP smoke
- IPv6 policy and support decision, if dual-stack remote endpoints are required

## Operational notes

`OutboundPolicy#resolve!` does **not** send HTTP requests. Do not call a
generic `Net::HTTP.start(uri.hostname, ...)` using the returned target.
That would discard the pinned-address condition and undo this protection.

Applications should not rely on this code until the new Client is implemented,
tested and released.

## Verification

`test/unit/client/outbound_policy_test.rb` tests URL/origin acceptance and rejection,
private-DNS/mixed records, URL query/secret handling, an intentionally conservative
IPv6 refusal and immutable target values.

Command (after bundle install on a supported Ruby):

```sh
bundle exec ruby -Itest test/unit/client/outbound_policy_test.rb
bundle exec rake test
```

The current `sdk-spike.yml` workflow runs the full Minitest suite for Ruby
3.3, 3.4 and 4.0; this slice must pass before merge.
