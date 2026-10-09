# Step 29-5i — Outbound Client bounded HTTP I/O and malformed response tests

> Scope: local TLS fixture / CI-only regression checks for the **unreleased** `A2A::Rails::Client`. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90). No GCP deployment, external host, production credential, or Cloud Run IAM change. Published RubyGems remains 0.2.0; **v0.3.x NO-GO**.

## Added negative cases

| Case | Required behavior |
| --- | --- |
| Response declares a Content-Length larger than the configured budget | Reject early with `response_too_large`. |
| HTTP/1.1 `Transfer-Encoding: chunked` response with no Content-Length and oversized JSON | Enforce the byte budget while reading the decoded body; reject. |
| `Content-Encoding: gzip` response | Reject compressed payloads even when advertised response is JSON; ensure Client requested `Accept-Encoding: identity`. |
| Valid but excessively deeply nested JSON | Reject with `invalid_json`, sanitize parser cause. |
| HTTP 204 with no JSON body | Never accept an absent JSON document as successful A2A JSON. |
| Content-Length claims more bytes than server sends before connection close | Reject the truncated reply, including when its received prefix is a valid JSON object. |
| Complete HTTP response headers, followed by delayed JSON body | Enforce read/total deadline and sanitize timeout cause. |
| TLS peer accepts socket but never reads a large POST | Large upload must not hang beyond bounded write/total timeout. Test verifies the TLS connection was accepted and uses no external host. |

Existing tests already cover DNS and credential callback deadlines, generic delayed response, invalid media types, malformed Content-Length, invalid JSON, request byte budgets, and an HTTP 403 that cannot leak its remote body.

## Verification

```sh
bundle exec ruby -Itest test/integration/client/pinned_https_transport_test.rb
bundle exec rake test
```

Review GitHub Actions Ruby 3.3/3.4/4.0, Rails 8.0/8.1, packaged-artifact and stable published Gem verification. On a failure, inspect and fix the exact fixture/runtime issue before merging.

## Scope limits

Tests use a disposable test-only loopback TLS server; they do not replace network egress proof or actual Cloud Run IAM-private interoperability (Step 29-5e). The slow-upload test is a bounded local simulation, not a guarantee across all slow/non-cooperative kernels, proxies, or remote servers.

Remaining #90 requirements include more adversarial HTTP/TLS/auth coverage, Rails ActiveJob concurrency, protocol semantics, real independent interoperability coverage, and separate release security review. **Issue #90 OPEN; v0.3.x NO-GO**.
