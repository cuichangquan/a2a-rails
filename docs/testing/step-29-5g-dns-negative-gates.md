# Step 29-5g — Outbound Client DNS / SSRF negative regression gates

> Scope: isolated **local/CI regression** hardening for the unreleased Client. No GCP resources, public endpoints, or credentials are required. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90). RubyGems stable remains `0.2.0`; **v0.3.x NO-GO**.

## Coverage added

| Case | Intended assertion |
| --- | --- |
| DNS replies contain CIDR (IPv4 `/24`, `/32`, IPv6 `/64`) | Fail closed with `invalid_dns_address`. `IPAddr.new` alone interprets CIDR as a **network**, not a socket-ready host answer. |
| DNS replies contain non-String values | Fail closed with a sanitized error; never trust arbitrary resolver objects. |
| DNS returns valid IPv4 mixed with a malformed answer | Reject **all** answers instead of picking the safe first address. |
| `Target#addresses` frozen array holds a mutable String | Regression: individual IPv4 strings must also be frozen; mutation must raise `FrozenError`. |
| DNS public in an earlier policy preflight but metadata IP on the subsequent transport attempt | Transport must **re-resolve** at request time; reject metadata before creating the HTTPS socket or evaluating `Authorization`. |

The rebind test does **not** dial the earlier public address or simulate an external DNS service. It asserts the negative branch on the actual production `OutboundPolicy` + `PinnedHttpsTransport` path with a deterministic fake resolver and a test-only local HTTPS listener that must receive no request.

## Existing coverage retained

Pre-existing unit/integration tests cover exact origin allowlisting, unapproved Card/RPC URLs, mixed public/private IPv4/IPv6 DNS, public-only dual-stack selection with IPv4 socket pinning, HTTPS TLS SNI and hostname verification, redirects blocked, and secret-safe errors. See `test/unit/client/outbound_policy_test.rb`, `test/integration/client/pinned_https_transport_test.rb`, and `test/unit/client/agent_card_resolver_test.rb`.

## Verification

```sh
bundle exec ruby -Itest test/unit/client/outbound_policy_test.rb
bundle exec ruby -Itest test/integration/client/pinned_https_transport_test.rb
bundle exec rake test
```

Record the GitHub Actions matrix outcome on the PR. Do not treat this local negative suite as a substitute for independent public CA/destination checks, TLS/auth/timeout adversarial matrix, Rails ActiveJob concurrency, or a full release security review.

## Decision

This is a narrow defense-in-depth and regression slice. It does **not** close Issue #90 or authorize v0.3.x publication, public/no-auth Cloud Run exposure, or changes to the existing GCP environment.
