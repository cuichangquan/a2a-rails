# Step 29-5c — Public HTTPS egress and negative security gates

> **Historical plan / status superseded:** The "NOT TESTED" public-DNS/CA language and the final decision below describe the status when Step 29-5c was originally authored. Step 29-5e has **subsequently PASSed** the real, original public-CA/DNS HTTPS path via ordinary Client constructor to an **IAM-private** Cloud Run Agent. Step 29-5g–j added local negative regression coverage. See the current [Step 29-5k release-gate reconciliation](step-29-5k-client-release-gates-audit.md). A **separate public/no-auth scenario is NOT RUN**; v0.3.x remains **NO-GO**. Historical checklist below is retained for auditability.

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

## Implementation correction (Step 29-5c follow-up PR)

The transport deadline is extended to include DNS resolution, credential callback evaluation, TLS connect, uploads and response parsing. Timeout exceptions from the DNS resolver and token callback are no longer misclassified as DNS/credential failures. The transport and DNS resolver wrappers strip causes from errors that might otherwise contain untrusted response text or credential-provider details.

[PR #92](https://github.com/cuichangquan/a2a-rails/pull/92) was merged with **29/29 CI passing**. Regression tests cover slow DNS, slow credential callbacks, rebinding after a public DNS result, malformed Content-Length, per-request parallel HTTPS credential separation and parser/TLS exception causes. These tests are **not** substitutes for a real public egress run, and do not prove every adversarial security gate (notably slow writes, multi-threaded Rails ActiveJobs or controlled public CA connectivity).

The protected public egress probe now has a dedicated default-policy public IPv4 + system CA TLS preflight and requires **both** a direct Message and Task + GetTask + text Artifact round trips. Collect the actual Rails Client dialed IP separately; the preflight opens its own socket, and a successful preflight does not certify the later Client's socket route. Until an operator provides a controlled endpoint, protected environment and isolated egress runner, this remains **NOT RUN**.

## Decision

- Public DNS + real CA + unmodified constructor: **NOT TESTED**.
- Complete adversarial negative gates: **NOT COMPLETE**.
- Permission to publish v0.3.x: **NO-GO**.
