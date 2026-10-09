# Step 29-5h — Outbound Client TLS and credential-negative regression gates

> Status: CI review slice for the **unreleased** `A2A::Rails::Client` only. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90). No new GCP deployment, live endpoint, or real credential is required. RubyGems stable stays 0.2.0; **v0.3.x NO-GO**.

## Added gates

| Gate | What is actually exercised |
| --- | --- |
| CA chain positive control | A test HTTPS server serves a fresh, valid leaf issued by a **locally trusted test CA**, with matching DNS SAN. The Client must accept it. |
| Trusted, expired leaf | The same CA signs a leaf whose validity is past; TLS must fail before any HTTP request. |
| Trusted, not-yet-valid leaf | Same trusted CA signs a future-dated leaf; TLS must fail before HTTP. |
| Trusted, mismatched SAN despite correct CN | A certificate with CN `trusted.example` but SAN `other.example` must fail name verification despite a valid trusted signing chain. A per-target bearer callback is evaluated locally but its value must **not** be transmitted or exposed in the sanitized error/cause. |
| Malicious `HTTP_PROXY` / `HTTPS_PROXY` environment | Run a **separate Ruby child process** with poisoned uppercase/lowercase proxy variables pointing to unreachable loopback port 1; actual pinned test-only TLS target must still respond. No shared test-process ENV mutation. |
| Unapproved Agent Card origin with credential callback | Real production `OutboundPolicy` rejects the origin before DNS resolution and before invoking the bearer callback. |

All TLS probes use disposable local TCP/TLS servers, a local test-only loopback policy, and a test CA generated in-process; the externally shipped Client continues to require public approved DNS/IP/CA. No `VERIFY_NONE` or relaxation of production URL policy is introduced.

## Prior guarantees still covered elsewhere

- Normal public constructor over actual approved public-CA HTTPS with private IAM: [Step 29-5e evidence](step-29-5e-public-window-readiness.md).
- IP pinning, TLS hostname/SNI, untrusted issuer, redirects, cross-origin auth, credential sanitization, mixed DNS/rebind: existing `pinned_https_transport_test.rb`, `outbound_policy_test.rb`, and [Step 29-5g](step-29-5g-dns-negative-gates.md).
- Per-request concurrent callback token separation: pre-existing transport integration test.

## Run locally

```sh
bundle exec ruby -Itest test/integration/client/pinned_https_transport_test.rb
bundle exec rake test
```

CI should pass Ruby 3.3/3.4/4.0, Rails 8.0/8.1 and packaged-artifact verification before merging.

## Remaining release blocks

This suite does **not** prove a real attacker-controlled proxy, every invalid TLS certificate construction (e.g., revocation), multi-threaded Rails ActiveJobs, log-sink privacy, slow socket writes, or the entire #90 adversarial checklist. It does not permit a public/no-auth Cloud Run test or v0.3.x RubyGems publication. Keep Issue #90 **OPEN** and release status **NO-GO**.
