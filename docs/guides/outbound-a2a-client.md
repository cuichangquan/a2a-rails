# Outbound Rails Client API — stable v0.3.0

> **Released (2026-10-10):** Stable [a2a-rails 0.3.0](https://rubygems.org/gems/a2a-rails/versions/0.3.0) now ships this outbound Client API. Previous stable **0.2.0** was Server-first and did not include this Client; [0.3.0.rc1](https://rubygems.org/gems/a2a-rails/versions/0.3.0.rc1) remains a historical prerelease. Gem publication **does not authorize anonymous/public production A2A Server exposure**; see [deployment #11](https://github.com/cuichangquan/a2a-rails/issues/11). [Verified stable release and SHA256](../release/v0.3.0-publication-record.md) · [Step 31-2 scoped security review](../release/v0.3.0-client-security-api-review.md).
>
> Tracking: [original Client design #84](https://github.com/cuichangquan/a2a-rails/issues/84), [client umbrella #75](https://github.com/cuichangquan/a2a-rails/issues/75), [stable readiness #120](https://github.com/cuichangquan/a2a-rails/issues/120).

To install the released stable Client, pin `gem "a2a-rails", "= 0.3.0"` in your Gemfile and test the actual host configuration. The [independent Client-only demo](https://github.com/cuichangquan/a2a-rails-client-demo) now pins **published stable 0.3.0**; the separate [Rails Echo Server demo](https://github.com/cuichangquan/a2a-rails-demo) also pins **0.3.0**. [Step 32 stable-to-stable Rails-to-Rails TLS CI](https://github.com/cuichangquan/a2a-rails-client-demo/actions/runs/38097502218) validates real isolated TLS with a test-only bridge, not public-DNS/public-CA deployment. For a tested standalone Client-only Rails 8 example, use [a2a-rails-client-demo](https://github.com/cuichangquan/a2a-rails-client-demo); its [Japanese Quick Start](https://github.com/cuichangquan/a2a-rails-client-demo/blob/main/docs/quickstart-ja.md) explains how to reproduce the independent TLS tests.

## Public Ruby interface (0.3.0)

```ruby
client = A2A::Rails::Client.new(
  agent_card_url: "https://example-agent.test/.well-known/agent-card.json",
  allowed_origins: ["https://example-agent.test"],
  authorization: -> { "Bearer #{Rails.application.credentials.dig(:a2a, :agent_token)}" },
  credential_origin: "https://example-agent.test",
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

The separate-process [Client-only Rails HTTP boot test](../../test/integration/client_only_rails_boot_test.rb) verifies that both inbound paths return HTTP 404. The existing Server HTTP suite verifies the default Server behavior. Published Gem **0.2.0 does not include this Client feature**; the public Client is shipped in **stable 0.3.0** (first introduced in prerelease 0.3.0.rc1).

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

## Release and operational boundaries

The public Client, codec and DTO/error mapping use the pinned HTTPS Agent Card resolver from Steps 29-3a–3c. Beyond public API unit contracts, the published RC1 has passed Client-only Rails boot, installed-Gem security, Ruby/Rails/PostgreSQL, independent native Python/Go SDK and isolated Rails-to-Rails TLS integration checks. See the [Step 31-2 evidence matrix](../release/v0.3.0-client-security-api-review.md) for what each test proves and what it **does not** prove.

**Release:** Stable `0.3.0` has been **published** with an immutable tagged source and verified Gem SHA256. [Release record](../release/v0.3.0-publication-record.md) covers the exact-package provenance, Ruby/Rails/PG/SDK checks and known risks. The previous stable `0.2.0` remains available unchanged.

**Limitations:** outbound HTTPS target sockets are pinned to approved public **IPv4**; IPv6-only destinations, SSE, push notifications, gRPC, polling/orchestration and automatic retries are unsupported. A timeout during `SendMessage` or `CancelTask` may follow a remote side effect; the host must reconcile state safely. Host security requires real credential issuer checks, business authorization, filtering outside Gem loggers, sensible budgets and durable storage/queue configuration where necessary.

**Production:** External security audit is **optional** for distributing this OSS Gem, not a claim of independent approval; public/no-auth Server operation remains a [separate NO-GO decision](https://github.com/cuichangquan/a2a-rails/issues/11) until the actual deployment meets its own security requirements.
