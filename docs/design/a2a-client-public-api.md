# Step 29-2 — Outbound Rails Client Public API Contract (v0.3 proposal)

> **Status: REVIEW CONTRACT ONLY — not implemented or released.** (2026-10-08)
>
> Depends on the [Step 29 design PR #76](https://github.com/cuichangquan/a2a-rails/pull/76) and the successfully run [Step 29-1 SDK spike PR #77](https://github.com/cuichangquan/a2a-rails/pull/77) ([real GitHub Actions](https://github.com/cuichangquan/a2a-rails/actions/runs/37746771841)).
> Tracking: [Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75).
>
> All Ruby code here is **proposed**, not available with `a2a-rails 0.2.0`.

## 1. Constraints and compatibility

1. Server remains server-first and backward compatible. The current inbound `A2A::Rails::Agent`, `Configuration#agent`, route handling, `Protocol::Agent2AgentAdapter`, and local Task Store do **not** change as part of this contract.
2. Outbound Client can be used in `app/services` and host ActiveJob without configuring an inbound Agent. No Rails controller, database table, or Gem Task Store is required to call another Agent.
3. Public values are Ruby types, never `::A2A::Client`, Faraday, Async, protobuf or `JsonSchema::Definition`. Transport remains pluggable behind an internal adapter.
4. A2A **protocol** v1.0 JSON-RPC only. Gem version v0.3 is unrelated to protocol v0.3.
5. The SDK 2.0.0 interoperability spike showed: explicit `A2A-Version: 1.0` works; omitting it on this server produced error code `-32009`. The Client adds the header for every RPC request. Agent Card retrieval and selected RPC interface URL are distinct.

## 2. Proposed consumer API

```ruby
# This is NOT implemented in a2a-rails 0.2.0.
# Use explicit origins, never a user-controlled URL.
client = A2A::Rails::Client.new(
  agent_card_url: "https://translator.example/.well-known/agent-card.json",
  allowed_origins: ["https://translator.example"],
  authorization: -> { "Bearer #{Rails.application.credentials.dig(:a2a, :translator_token)}" },
  open_timeout: 3,
  read_timeout: 10,
  total_timeout: 15
)

card = client.agent_card # frozen, protocol-key-normalized Hash
result = client.send_message(
  message: {
    message_id: SecureRandom.uuid,
    role: "ROLE_USER",
    parts: [{ text: "Hello", media_type: "text/plain" }]
  },
  configuration: { accepted_output_modes: ["text/plain"] }
)

if result.kind == :task
  # Remote identifiers are not local Task Store identifiers.
  task_id = result.task.fetch(:id)
  current = client.get_task(id: task_id, history_length: 0)
  # App schedules subsequent polling itself, if current is still working.
else
  direct_message = result.message
end

page = client.list_tasks(
  context_id: "known-context-id",
  status: "TASK_STATE_WORKING",
  page_size: 20,
  include_artifacts: false
)
next_page = client.list_tasks(page_token: page.next_page_token) unless page.next_page_token.empty?
cancelled = client.cancel_task(id: "known-running-task-id")
```

### Public method signatures (proposal)

```ruby
A2A::Rails::Client.new(
  agent_card_url:, allowed_origins:,
  authorization: nil, card_authorization: nil,
  open_timeout: 3, read_timeout: 10, total_timeout: 15
)
# Throws ConfigurationError for unacceptable options before any request.

client.agent_card
client.send_message(message:, configuration: nil, metadata: nil)
client.get_task(id:, history_length: nil)
client.list_tasks(context_id: nil, status: nil, page_size: nil,
                  page_token: nil, history_length: nil,
                  status_timestamp_after: nil, include_artifacts: nil)
client.cancel_task(id:, metadata: nil)
```

- Use `snake_case` Ruby-facing keys for known A2A fields; `nil` optional arguments are omitted, never blindly serialized as JSON `null`.
- `message` is **a complete A2A Message**, not a String. Require nonempty `message_id`, `role == "ROLE_USER"`, nonempty `parts`, and exactly one of `text/raw/url/data` per part; support file, data and text. Do not auto-generate IDs inside this first contract: callers need stable IDs to investigate ambiguous timeout outcomes.
- Use the official A2A `status` strings and include non-terminal states `TASK_STATE_INPUT_REQUIRED` / `TASK_STATE_AUTH_REQUIRED` and `TASK_STATE_UNSPECIFIED`; do not coerce them to a local terminal enum. Unknown *future* string values may be preserved but are never automatically called terminal.
- `send_message` defaults to protocol behavior. Caller can set `configuration[:return_immediately]`; the Client must not insert its own polling loop.
- `history_length: 0` requests no history; preserve distinction from `nil`. `page_size` validated as 1..100. `include_artifacts: false` is preserved explicitly.
- The selected Agent Interface's optional `tenant` is injected into **every** RPC request, including Get/List/Cancel. The application cannot override it. If the pinned SDK cannot carry it, reject that interface rather than silently dropping it.
- `metadata` keys and arbitrary nested `data` keys are **opaque** strings as provided; never symbolize, rename or truncate business-defined JSON. Protocol-defined keys become snake_case symbols. Extension keys not understood by the Client remain available as string keys. Reject ambiguous collisions such as `message_id` and `messageId` in the same object.
- All received values are defensive, immutable copies; application mutation cannot corrupt the Client's internal cache/state. JSON numeric/boolean/null values in `data` are preserved.
- `agent_card` retrieval may cache only within this Client instance with a documented bounded lifetime, to be defined/tested before production. No process-global card cache or accidental cross-tenant credential reuse.

## 3. Return objects — shape and invariants

### SendResult

```ruby
# A2A::Rails::Client::SendResult, immutable value object
result.kind       # :task OR :message (no other value)
result.task       # Hash (snake_case protocol keys) if :task; else nil
result.message    # Hash if :message; else nil
```

Exactly one of `task` and `message` is present; a malformed envelope with zero or two must raise `InvalidResponseError`. Preserve optional Task history and artifacts, Message task/context linkage, metadata and unknown protocol extension fields.

### Task (plain frozen Hash)

```ruby
{
  id: "task-123",
  context_id: "ctx-123", # may be absent
  status: {
    state: "TASK_STATE_SUBMITTED",
    timestamp: "2026-10-08T00:00:00Z" # optional
  },
  artifacts: [ # optional; do not substitute [] when omitted
    { artifact_id: "artifact-1", parts: [{ text: "Hello" }] }
  ],
  history: [] # optional
}
```

The above shape is a **sample**: an empty/absent field must not be conflated with a field explicitly present. Unknown future states remain visible. File `raw` contents stay encoded as base64 string in JSON-facing values; the Client does not fetch remote URLs or decode binary automatically.

### ListResult

```ruby
# A2A::Rails::Client::ListResult, immutable value object
page.tasks           # Array of Task Hashes (possibly empty)
page.next_page_token # String, "" for final page
page.page_size       # Integer
page.total_size      # Integer
```

Required pagination fields follow the A2A protocol. Do not treat the empty string as nil. The server owns filtering, result ordering and access control.

### Agent Card

`agent_card` returns a frozen Hash with snake_case **protocol** keys such as `:name`, `:supported_interfaces` and `:security_schemes`; nested unknown/opaque objects are preserved. The Client must not return raw unvalidated JSON or public SDK schema objects.

## 4. Explicit error taxonomy

All errors under `A2A::Rails::Client::Error < A2A::Rails::Error` (new classes, not inbound `TaskError`).

| Error | Condition | Safe metadata |
| --- | --- | --- |
| `ConfigurationError` | Invalid URL, origin/options, callback type | no untrusted URL reflection |
| `InvalidInputError` | Invalid message oneof, Task ID, filters | parameter name only |
| `DiscoveryError` | Missing/broken Agent Card | safe category |
| `UnsupportedInterfaceError < DiscoveryError` | No permitted JSONRPC 1.0 interface; unsupported tenant | requested protocol only |
| `TransportError` | Network, TLS or closed connection | operation, safe cause category |
| `TimeoutError < TransportError` | Total/connect/read deadline | `operation`, `may_have_executed` |
| `AuthenticationError` | Remote HTTP 401/403 or verified auth rejection | status and operation |
| `RemoteError` | Valid A2A error envelope, including `-32009` | A2A code, operation; message sanitized |
| `InvalidResponseError` | Malformed JSON, bad envelope/oneof, invalid Task, oversized payload | operation, reason category |

- A timeout **never proves** `SendMessage` or `CancelTask` was not applied. Represent `may_have_executed: true` on timeout of those operations; other operations need not claim side effects.
- Do not automatically retry `SendMessage` or `CancelTask`; no implicit retry/polling for Get/List in v0.3 first slice.
- Preserve A2A numeric remote error codes where available. Never log or expose SDK stack traces, tokens, raw request/response bodies or untrusted remote message content.
- `AuthenticationError` does not mean the Gem obtains credentials automatically. Authorization policy remains the remote Agent's responsibility.

## 5. Credential and origin boundary

- `agent_card_url` must be a configured absolute URL; production **HTTPS**. Reject userinfo, fragments and unexpected query strings. `allowed_origins` is required and contains **exact scheme + host + optional port** (no wildcard/suffix matching). Normalize default HTTPS port; never trust Agent Card hostname claims.
- Validate and authorize **both** discovery URL and the selected `supported_interfaces[].url` independently; the latter may have another origin. Fail closed unless both are allowlisted; never forward credentials across origins without a **target-specific** credential binding.
- The `authorization` callback returns a bearer/header value **only** for the authenticated RPC origin. It is evaluated per request and must not be cached/shared with another origin. `card_authorization` is a separate opt-in callback for protected Agent Cards; by default public discovery receives no secret.
- All endpoint/redirect and network policy decisions must be enforced **at connection time**, including DNS results; reject redirects, avoid private/loopback/link-local/metadata addresses by default, and prevent proxy bypass and DNS rebinding. In local test-only scenarios, use an explicitly injected test transport rather than relaxing production defaults via ENV.
- TLS verification always on; strict connect/read/total timeouts and bounded request/response bytes, JSON depth and redirects (zero by default). Transport implementation must demonstrate these guarantees in Step 29-3.
- SDK 2.0.0 logs `Client #{op.name}: #{params}` via `Console.info`, potentially leaking private content. Do **not** use that path unsafely or mutate global Console levels during concurrent requests. If logging cannot be isolated, replace SDK transport **inside the outbound adapter**.
- No API credentials in Agent Cards, Tasks, URLs, audit logs or exceptions.

## 6. Client-only Rails app and Server backward compatibility

To use the Gem only as an outbound client, propose:

```ruby
A2A::Rails.configure do |config|
  config.server_enabled = false
end
```

- **Existing users remain `server_enabled = true` by default**; their mounted endpoints and Agent configuration behavior are unchanged.
- For Client-only mode, no inbound `GET /.well-known/agent-card.json` or `POST /a2a` should be mounted by the Engine; no server Agent should be required. The new `Client` must have no dependency on `Runtime` or `Task::Store`.
- Rails initializer load order matters: do not hardcode an Engine `routes.append` decision before the host's configuration is available. Verify Rails 8.0/8.1 boot and mounted routes before locking down the implementation.
- Avoid exposing a new broad global `config.client` singleton that could mix tenant credentials in multitenant host Rails apps. Clients are host-created instances.

## 7. Acceptance test matrix (future implementation)

| Scenario | Contract / expected behavior |
| --- | --- |
| No inbound Agent + Client-only mode | boots and works, no inbound A2A routes |
| Existing Server-only host | routes, configuration, Store and API unchanged |
| Card with multiple interfaces | first permitted JSONRPC/1.0 URL selected; exact URL used |
| Card from approved origin points to untrusted origin | fail before outbound RPC; no credential leak |
| Card declares `tenant` | inject it on **all** RPCs or explicitly reject |
| No matching interface | `UnsupportedInterfaceError` |
| SendMessage Task | `kind == :task`, completed/working states preserved |
| SendMessage direct Message | `kind == :message`; Task nil |
| SendMessage result has both/neither | `InvalidResponseError` |
| Rich Part | text / data / raw / URL oneof and custom metadata preserved |
| ListTasks | page_size, total_size, empty next_page_token preserved |
| `history_length: 0`, `include_artifacts: false` | no accidental omission of explicit values |
| Remote `INPUT_REQUIRED` / `AUTH_REQUIRED` | exposed without forcing terminal status |
| Missing `A2A-Version` in SDK by default | Client sets header `1.0` |
| Timeout after SendMessage | `TimeoutError` with ambiguous execution; no retry |
| Invalid TLS / blocked DNS / redirects / oversized reply | fail closed and emit no private data |
| `Console.info` SDK logging | no private parts/tokens in logs under concurrency |

Fixture-level sample vectors live in `test/contract/client_api/fixtures/` and their **schema sanity checks** live in `spikes/a2a_client_v03/public_contract_vectors_test.rb`. These checks validate **examples only**, **not** the existence or correctness of a Client implementation. The production Client must later run **separate executable contract tests against its own API**.

## 8. Next steps / unresolved implementation dependencies

- **29-2:** review this contract before changing runtime code. Proposed default timeouts are design inputs and must be enforced/tested, not assumed to be safe.
- **29-3:** implement the safe discovery/connection policy and negative security tests first.
- **29-4:** implement SDK-independent DTOs and operations; bind them to the transport.
- **29-5:** independent Python/Go server interoperability and client-only Rails Engine boot integration.
- Release still **NO-GO** for public-production Client until SSRF, TLS, version, credential/logging and size-limit gates pass.

## Source of truth

- [A2A v1.0.1 official specification](https://a2a-protocol.org/v1.0.1/specification/) — Agent Interfaces, ListTasks pagination, Task states and oneof.
- [Step 29-1 real SDK smoke](https://github.com/cuichangquan/a2a-rails/actions/runs/37746771841).
- [Step 29 architecture design](a2a-client.md).
