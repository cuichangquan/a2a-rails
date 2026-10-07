# Step 16-4 — A2A HTTP request hardening

> **Status:** Step 16-4 is merged into the unreleased `main` branch via [PR #16](https://github.com/cuichangquan/a2a-rails/pull/16). These safeguards are **not** included in published RubyGems `a2a-rails 0.1.0`.
>
> **Security scope:** request input limits and data handling, **not** a guarantee that the server is production-ready. Production still requires verified authentication, business authorization, TLS, traffic controls, the Agent Card security scheme and additional reviews tracked in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).

## HTTP request boundary

The Rails controller enforces the following checks **before** it invokes the application's authentication callback or the A2A SDK:

| Control | Default behavior |
| --- | --- |
| Body size | 1 MiB (`1_048_576` bytes) |
| Configurable size | Integer from 1 to 16 MiB |
| Content-Type | `application/json` (optional parameters such as `charset=UTF-8` permitted) |
| Content-Encoding | Absent or `identity` only (compressed bodies are rejected) |
| Content-Length | Rejects invalid lengths and mismatches |
| Unknown/chunked body size | Reads at most `max_request_bytes + 1` bytes to detect oversize input |

The guard buffers the bounded body in `StringIO` and passes that copy to the A2A SDK; it does not allow the SDK to read arbitrarily large bodies. It also parses the bounded JSON **once for a limited preflight shape check**: malformed `SendMessage` Parts are rejected before upstream SDK middleware can dereference non-object values. Full protocol validation still belongs to the SDK and RequestHandler.

### Configuration

```ruby
A2A::Rails.configure do |config|
  config.agent = "YourAgent"
  config.max_request_bytes = 1_048_576 # default: 1 MiB
end
```

Choose a smaller limit for text-only Agents as appropriate; avoid raising the cap without reviewing memory, concurrency and handler costs. A value outside 1..16 MiB is treated as invalid configuration (fail closed).

### HTTP failures

- `413 Payload Too Large` — declared or measured size exceeds the cap.
- `415 Unsupported Media Type` — wrong Content-Type or compressed input.
- `400 Bad Request` — invalid/mismatched content length or missing/invalid body stream.
- `500 Request validation unavailable` — invalid request-size configuration, without leaking the underlying exception.

These are HTTP boundary errors **before JSON-RPC parsing**, so they do not carry a JSON-RPC request ID. Responses continue to use `Cache-Control: no-store`.

## A2A request parameter validation

In addition to the SDK schema checks, the internal RequestHandler rejects invalid types before creating a Task:

- `message.taskId` / `message.contextId` must be Strings when present.
- `message.metadata` and `part.metadata` must be JSON objects when present.
- Text parts must be objects with a String `text`; unsupported Part types remain rejected.
- `part.mediaType` must be a String when present.
- `ListTasks.contextId` and `ListTasks.pageToken` must have appropriate types.
- `ListTasks.includeArtifacts` must be boolean when provided.

The wire protocol remains defined by A2A v1.0; these checks are defensive safeguards for missing/invalid values, not a second protocol implementation.

## Pagination memory cap

The process-local `Task::MemoryStore` now caches at most 128 pagination snapshots per process. When this cap is reached, the oldest snapshot token becomes invalid. Clients should treat expired pagination tokens as invalid and restart listing.

**Important:** the Memory Store still keeps **Tasks** in process memory with no configured retention policy and does not share them across Rails processes. This feature caps pagination snapshots only. Durable Task storage, bounded Task retention and multi-process production semantics remain separate work.

## Sensitive logging

Unexpected Handler exceptions are logged with the Task ID and exception **class only**; raw exception messages and stack traces are no longer emitted by this Gem's Task lifecycle logger by default. Applications must still review their own Handler and middleware logs, error trackers and access logs for credential leakage.

## Traffic and operational controls (host responsibility)

The Gem does **not** implement a distributed rate limiter, ingress queue or end-to-end Handler execution deadline. For public-facing deployments, enforce controls at a trusted gateway and in the host application:

1. Require HTTPS/TLS and validate proxy forwarding/host configuration.
2. Authenticate callers and authorize each business action. Use unique tenant-qualified principal IDs.
3. Rate-limit by verified principal (and trusted network identity), with a documented `429` / `Retry-After` response.
4. Apply bounded request concurrency, Handler timeouts, and database/LLM cost quotas.
5. Bound Task retention, cursor lifetime, and long-running work in a persistent store before scale-out.
6. Keep request bodies, Authorization headers and secrets out of HTTP access logs, observability events, and error trackers.

Do not rely on IP-only throttling for principal-aware authorization, or on per-process Ruby memory counters as your sole distributed rate limit.

## Tests

- RequestGuard unit tests cover declared and unknown-size bodies, size-boundary behavior, Content-Type/Content-Encoding and invalid limits.
- Protocol integration tests cover malformed text parts, metadata, Task and pagination query fields.
- Memory Store tests cover capped pagination snapshots.
- Rails HTTP smoke tests cover `413`, `415`, sanitized `500` and the existing protected Task flow.
- The packaged Gem smoke continues to verify the published Quick Start contract (once CI completes).

## References

- [A2A v1.0 specification](https://a2a-protocol.org/v1.0.0/specification/)
- [Authentication / Task isolation guide](authentication.md)
- [Roadmap](../../ROADMAP.md)
- [Security Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11)
