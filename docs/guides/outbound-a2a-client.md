# Step 29-4a — Outbound Rails Client API (unreleased implementation)

> **Status: implementation PR under review; NOT published or approved for production.**
>
> Tracking: [Issue #84](https://github.com/cuichangquan/a2a-rails/issues/84) / [Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75).
> The latest published RubyGems artifact remains **a2a-rails 0.2.0**, which does **not** contain this API.

## Proposed public Ruby interface

```ruby
client = A2A::Rails::Client.new(
  agent_card_url: "https://example-agent.test/.well-known/agent-card.json",
  allowed_origins: ["https://example-agent.test"],
  authorization: -> { "Bearer #{Rails.application.credentials.dig(:a2a, :agent_token)}" },
  open_timeout: 3, read_timeout: 10, total_timeout: 15
)

card = client.agent_card
result = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "Hello" }]
})

case result.kind
when :task
  task = client.get_task(id: result.task.fetch(:id), history_length: 0)
when :message
  direct = result.message
end

page = client.list_tasks(page_size: 20, include_artifacts: false)
client.cancel_task(id: "remote-task-id")
```

Only use **explicitly approved HTTPS Agent origins**. Remote task IDs are scoped to the remote Agent, not the local Rails Task Store.

If Agent Card discovery and the advertised RPC endpoint are on different origins, supply both origins in `allowed_origins:`. Credential callbacks are not forwarded to that different origin automatically. Bind an RPC token explicitly using `credential_origin: "https://rpc.example"`; use `card_authorization` and `card_credential_origin` independently for non-public Agent Cards. No token is sent for public discovery by default. Remote Agent authentication and authorization remain the remote server's responsibility.

## Using a Rails app only as an outbound Client

Existing Rails Server installations continue to use `server_enabled = true` by default. In a Rails application that **only calls** external Agents, add:

```ruby
# config/initializers/a2a_rails.rb
A2A::Rails.configure do |config|
  config.server_enabled = false
end
```

The host app then does **not** mount inbound `/.well-known/agent-card.json` or `/a2a`, and does not require `config.agent`. Outbound Client instances can still be constructed in services and ActiveJob. This setting is deliberately per Rails application and is not an automatically inferred mode.

The separate-process [Client-only Rails HTTP boot test](../../test/integration/client_only_rails_boot_test.rb) verifies that both inbound paths return HTTP 404. The existing full Server HTTP integration suite verifies backward compatibility with the default setting. A staged Ruby/Gem build on main does **not** mean RubyGems 0.2.0 contains this feature.

## Returned values

- `SendResult#kind` is exactly `:task` or `:message`; the other value is `nil`.
- `get_task` and `cancel_task` return deeply immutable Hashes with known A2A fields converted to snake_case symbol keys.
- `ListResult` exposes frozen `tasks`, `next_page_token` (including the empty string), `page_size` and `total_size`.
- `agent_card` returns a frozen Hash. Unknown or nested custom `data` and `metadata` keys remain opaque strings; they are not renamed/symbolized.
- All Task states, including `TASK_STATE_INPUT_REQUIRED`, `TASK_STATE_AUTH_REQUIRED` and unknown future states, remain visible. No implicit polling, retry or automatic continuation.
- The caller supplies the message ID, not the Gem, to make ambiguous timeout outcomes traceable.
- Optional `history_length: 0` and `include_artifacts: false` are transmitted as explicit values.

## Errors

All external API exceptions are under `A2A::Rails::Client::Error`, not the inbound Rails Task errors:

- `ConfigurationError` / `InvalidInputError`
- `DiscoveryError` / `UnsupportedInterfaceError`
- `TransportError` / `TimeoutError#may_have_executed`
- `AuthenticationError#status` / `RemoteError#code`
- `InvalidResponseError`

Request/response bodies, Authorization values and untrusted server error descriptions must never be embedded in errors/logs.

## Credential scopes and host logging

Outbound Client has **separate credential callbacks and exact HTTPS origins** for
Agent Card discovery and JSON-RPC. Only bind each callback to the approved
origin that is meant to receive it. A callback should read short-lived credentials
when the request is made; never capture or store a bearer token as a job argument.
The Client's per-request `Net::HTTP` transport does not enable wire debug output.

**Rails and background workers are separate logging boundaries:** the Gem
cannot control an application's `Rails.logger`, ActiveJob argument logging,
third-party error reporters, reverse proxies, APM/tracing middleware or external
HTTP logging. These systems can leak sensitive data **if your application supplies
it to their log APIs**. In particular:

- Queue only non-secret, serializable reference IDs. Inside each job, look up
  authorized business data and instantiate the Client with scoped credentials.
  **Do not enqueue** full A2A Messages/Parts, bearer tokens, credential callbacks
  or a Client instance. Disable or filter job argument logging as appropriate.
- Configure Rails `filter_parameters` for `authorization`, `token`,
  `secret`, `password` and other app-specific fields. Explicit filtering is
  still needed in APM, proxy, queue and error reporting systems; Rails parameter
  filters alone do not govern all logs.
- Log safe operation categories and opaque job/task IDs only. Avoid logging
  raw Agent Cards, RPC request/response JSON, Part text/File/Data, Authorization
  headers, untrusted error messages, exception causes or TLS wire traces.
- `TimeoutError#may_have_executed` means a SendMessage/CancelTask may already
  have run. Reconcile with the remote Task and application idempotency policy;
  do **not** automatically retry an ambiguous side effect.

[Step 29-5m's local log-sink checks](../testing/step-29-5m-credential-log-privacy.md)
cover same-process ActiveJob `perform_now` logging, notifications and real
local TLS credential separation. They are **not** a guarantee for every possible
host logger, queued multi-process worker or production observability pipeline.

## State and release blockers

Step 29-4a adds the Ruby façade, codec and DTO/error mapping. It uses the internal pinned HTTPS / Agent Card resolver from Steps 29-3a–3c. Unit tests exercise **actual public method signatures and normalized fixture examples**, not merely the old reference fixture checker.

**It is not yet production-ready**. The next slices must explicitly cover Client-only Engine boot/route opt-out (default Server behavior unchanged), independent HTTPS remote Agent interoperability, malformed payload/pagination/rich parts, credential boundaries, SSRF regressions and full release security review. No RubyGems push or release is implied by merging this PR.
