# Step 29-5m — Outbound Client credential isolation and ActiveJob log-sink privacy

> **Unreleased Client only.** Local/CI security regression tests and host guidance; no public endpoint, production credentials, RubyGems publication or GCP resources. This is one **partial** security gate under [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) and the [Step 29-5k audit](step-29-5k-client-release-gates-audit.md). **v0.3.x NO-GO.**

## Security boundary being checked

The Client's transport and Agent Card resolver have separate `card_authorization`
and `authorization` callbacks, each constrained to an explicitly approved,
exact Card/RPC HTTPS origin. Neither caller-supplied credentials nor Message
Parts should appear in the Client's own exceptions or the **representative
ActiveJob framework log sinks** when jobs are given only safe reference IDs.

### Evidence added

| Test | Positive and negative assertions |
| --- | --- |
| Four concurrent **real local HTTPS** sessions, each with separate Card and RPC servers | Each Agent Card GET receives **only** its corresponding Card token; each JSON-RPC POST receives **only** its corresponding RPC token. All four distinct message IDs and reply task IDs remain isolated. No unintended extra HTTP request is observed. |
| Four concurrent `ActiveJob::Base.perform_now` executions with an actual tagged ActiveJob logger and subscribed `*.active_job` notifications | Jobs are passed **only opaque numeric reference IDs**, not credentials/Part bodies or Client instances. Assertions require actual `perform.active_job` notifications, and capture both log text and notification payloads. Neither source may contain sent bearer tokens, Part content, an upstream HTTP 403 response body nor a failing credential callback's exception message. |
| Deliberate callback failures and remote HTTP 403s | Callback failures are sanitized into `credential_failure`; HTTP 403s disclose status only. Public-facing errors have **nil causes**, and the error text excludes each secret. The controlled TLS server does receive the expected Authorization and message body for **authorized** POSTs, demonstrating real network transmission without log disclosure. |

The tests use a **test-only pinned 127.0.0.1 HTTPS policy** and ephemeral
self-signed local certificates. No real secrets or production destinations
are used. The log-sink test deliberately keeps callback secrets and raw
Messages in a temporary test-only in-memory registry; ActiveJob's job
arguments contain reference IDs, not those objects.

### Existing evidence retained

- Rejected origins and mixed DNS must not evaluate the token provider.
- Origin mismatches do not send an Authorization header; card and RPC
  credentials do not silently cross origins.
- TLS and invalid JSON errors have sanitized causes/messages.
- The underlying transport uses `Net::HTTP.new(host, port, nil)`,
  `VERIFY_PEER`, hostname verification and no wire-debug output.
- The Step 29-5j six-thread ActiveJob public-Client test verifies
  unique message and RPC IDs without queueing Client objects.

## Verify

```sh
bundle exec ruby -Itest test/integration/client/pinned_https_transport_test.rb
bundle exec rake test
```

Review GitHub Actions matrix (Ruby 3.3/3.4/4.0; Rails 8.0/8.1; packaged Gem;
installed stable 0.2.0 security/PG; local Python/Go interoperability) before
merge. Test results are recorded on the PR / Issue #90.

## Explicit limits and operational guidance

**Passing these checks does NOT prove confidentiality across every real Rails
host, reverse proxy, queue backend, multi-process worker, log agent, APM or
error reporting system.** The test captures a specific ActiveJob logger and
ActiveSupport notification set, **not arbitrary Rails.logger/APM hooks**.
Since the Gem cannot filter host-owned logging calls, applications should
queue non-secret IDs, create a Client and fetch credentials inside job
execution, configure all logging surfaces, and avoid logging raw RPC JSON,
Part payloads, bearer headers and upstream diagnostic bodies.

Real serialized Solid Queue/Sidekiq **outbound** Client workflows remain
[Step 29-5o](step-29-5k-client-release-gates-audit.md); advanced official
Python/Go data and Task semantics remain Step 29-5n; independent release
review remains Step 29-5p. The **separate public/no-auth** Cloud Run
test has **not** been approved/executed.

**Issue #90 OPEN; v0.3.x NO-GO; stable RubyGems 0.2.0 unchanged.**
