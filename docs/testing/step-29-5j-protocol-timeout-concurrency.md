# Step 29-5j — Outbound Client protocol errors, ambiguous timeouts, parallel ActiveJob calls

> Scope: offline/CI regression gates for the **unreleased** `A2A::Rails::Client`. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90). No new GCP resources, Cloud Run changes, production tokens or public/no-auth tests. Published stable RubyGems remains 0.2.0; **v0.3.x NO-GO**.

## Added verification

| Case | Assertion |
| --- | --- |
| Direct SendMessage returns a Message with a Part containing both `text` and `data` or `url` | **Runtime fix** rejects malformed oneof as `InvalidResponseError(:invalid_message_part)`, before returning data to the Rails app. Empty/malformed direct Parts rejected as well. |
| JSON-RPC returns mismatched request ID/version or invalid `error.code` type | `AgentCardResolver` rejects the envelope and never surfaces untrusted error strings. Caller request IDs remain unchanged. |
| Resolver raises a deadline error for SendMessage / CancelTask / GetTask / ListTasks | Public API raises a sanitized typed TimeoutError with `may_have_executed: true` only for **SendMessage / CancelTask**. One invocation is recorded, and the original supplied message ID is preserved. |
| Actual local HTTPS RPC SendMessage / CancelTask received by server, then response stalls | Real pinned Net::HTTP path returns a typed potentially-executed timeout. The server observes the complete JSON-RPC POST and its original `messageId` / task ID. |
| Six concurrent `ActiveJob::Base.perform_now` executions on shared Client test facade | Unique outgoing JSON-RPC IDs, no mix-up of original job `messageId`s and normalized direct responses. |

Existing `PinnedHttpsTransport` still explicitly sets `max_retries = 0`; this slice adds no automatic HTTP or task retry. An observed single local RPC request is **not** a proof against every network/kernel retry race. Timeout does not mean a remote side effect was rolled back; callers must reconcile uncertain Task state instead of automatically retrying.

## Boundaries

- All HTTPS checks are local-only and use an explicitly injected test-only pinned-loopback policy. The public constructor does **not** expose that injection.
- Concurrent ActiveJob calls use `perform_now` from independent Ruby threads. This exercises ActiveJob instrumentation and same-process concurrency, **not** queued serialization, Solid Queue/Sidekiq worker processes or multi-host execution. The tests pass a Client object via `perform_now`; production queued jobs should instantiate a Client per job and supply only serializable, non-secret identifiers in job arguments.
- Direct Message Part oneof validation has been tightened. The validation of nested Task/Artifact Parts remains a separate protocol review item.
- No claims of full SSRF, authorization, TLS, timeout or log-sink security coverage.

## Verification

```sh
bundle exec ruby -Itest test/unit/client/public_api_test.rb
bundle exec ruby -Itest test/unit/client/agent_card_resolver_test.rb
bundle exec ruby -Itest test/integration/client/pinned_https_transport_test.rb
bundle exec rake test
```

Require Ruby 3.3/3.4/4.0, Rails 8.0/8.1, installed-artifact/production security, PostgreSQL, Python/Go interop, and existing official TCK workflows to pass before merge. **Issue #90 remains OPEN; v0.3.x remains NO-GO.**
