# Step 29-5c — Public HTTPS egress and negative security gates

Status: **OPEN / NO-GO**. Parent: [#90](https://github.com/cuichangquan/a2a-rails/issues/90). The stable published gem remains **0.2.0**; this document does not approve a new release.

## Evidence already established

- [PR #89](https://github.com/cuichangquan/a2a-rails/pull/89): original Agent Cards, native HTTPS, official Python and Go servers. Both services were loopback and required a test-only resolver and trust root.
- Default production policy blocks loopback/private DNS. The TLS/SNI correctness established by PR #89 does **not** demonstrate ordinary public DNS plus a public CA using the unmodified Client constructor.

## Mandatory positive proof

Use an endpoint owned and operated by the project owner: an allowlisted **public IPv4 DNS name** with a genuine trusted public CA certificate, serving the original Agent Card and its advertised JSON-RPC interface. Do not use a third-party public A2A agent without explicit permission.

- Record the exact Card and RPC endpoint URLs, hostname, certificate issuer / validity, public DNS response and contacted IP without including credentials.
- Run the ordinary `A2A::Rails::Client.new(agent_card_url:, allowed_origins:)` entrypoint, not an internal resolver/policy/transport override.
- Check card discovery, original selected interface protocol and URL, direct Message, Task creation, GetTask, and returned Artifact.
- Constrain network egress with a separately provisioned firewall or controlled runner. A Ruby allowlist alone is not an external egress firewall.
- Require proof that TLS peer verification and hostname verification remain enabled. No `VERIFY_NONE`, custom development CA, hosts-file mappings, resolver overrides or HTTPS bridges.
- Preserve immutable evidence of code SHA, workflow run, Ruby/Rails versions and public endpoint configuration. Never print bearer tokens, request Parts or remote error bodies.

## Additional negative security gates

1. SSRF: reject Card origin outside allowlist, advertised RPC origin outside allowlist, private/link-local/metadata/reserved IPv4, mixed DNS answers, malformed URL, redirect, unexpected interface protocol/version. Prove socket connects to the pinned IP even when DNS records change.
2. TLS: invalid or expired certificates, untrusted issuer, mismatched SAN/SNI, certificate for another host, HTTP proxy environment injection.
3. Credentials: exact per-origin binding, independent Card and RPC callbacks; rejected targets never evaluate callbacks; exceptions/logs/causes never reveal credentials or Parts; concurrency isolation.
4. I/O: open/read/write/total deadlines including DNS lookup and credential provider, bounded request and response, invalid Content-Length, chunked overflow, oversized/deep/invalid JSON, compression refusal, content-type validation.
5. Protocol: preserve caller message IDs, no automatic HTTP retries, send/cancel timeouts marked potentially executed, oneof validation, ListTasks pagination, nonterminal states, CancelTask, rich File/Data and nested extension keys against both official SDKs.
6. Release: Ruby 3.3/3.4/4.0, Rails 8.0/8.1, packaged-artifact and PostgreSQL checks; independent security review and distinct v0.3.x go/no-go decision.

## Implementation observation requiring regression proof

The current `PinnedHttpsTransport#perform` begins its `Timeout.timeout(total_timeout)` **after** DNS resolution and credential callback execution, so the configured total request timeout does not currently include those stages. In addition, cause chains of rethrown internal network/JSON exceptions should be reviewed to avoid exposing untrusted response snippets in logs. Fix and demonstrate with tests before marking this gate PASS.

## Decision

- Public DNS + real CA + unmodified constructor: **NOT TESTED**.
- Complete adversarial negative gates: **NOT COMPLETE**.
- Permission to publish v0.3.x: **NO-GO**.
