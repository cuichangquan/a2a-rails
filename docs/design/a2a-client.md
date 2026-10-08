# Step 29 — Outbound A2A Client Design (v0.3 proposal)

> Status: **design proposal / not implemented** (2026-10-08).  
> Tracking issue: [#75](https://github.com/cuichangquan/a2a-rails/issues/75).  
> Baseline: published `a2a-rails 0.2.0` is an inbound Rails A2A Server; its public API and release status are unchanged.

## Review status and detailed public contract

- Step 29-1 [published SDK / independent Rails Demo HTTP spike](https://github.com/cuichangquan/a2a-rails/actions/runs/37746771841) **PASS**. The actual `A2A-Version: 1.0` header is required for the pinned demo.
- Step 29-2 [precise Client API, DTO, error and security contract](a2a-client-public-api.md) is proposed in [Draft PR #78](https://github.com/cuichangquan/a2a-rails/pull/78), with self-contained reference fixtures. That CI checks **fixture examples only**, not a product Client.
- Future Step 29-3 remains the release-blocking outbound transport policy; the public Client is **not implemented**.

## Goal and non-goals

Allow **any** Rails 8 application to call remote A2A v1.0 Agents, whether or not that Rails app also exposes an A2A Server. This is a general-purpose Rails integration, not a Shopping Agent, LLM platform, orchestrator, or multi-agent workflow engine.

Keep the existing inbound `A2A::Rails::Protocol::Agent2AgentAdapter` unchanged. Add a separate outbound client boundary rather than exposing `A2A::Client` or its schema objects in the Rails-facing API.

```text
Rails Application / Service / Job
               |
        A2A::Rails::Client            <-- proposed public API
               |
     Client discovery / policy
               |
     Protocol::ClientAdapter           <-- SDK boundary
               |
    agent2agent 2.0.0 client
               |
       HTTPS JSON-RPC v1.0
               |
      Remote A2A Agent Server
```

## First-slice scope

| Feature | Proposal | Notes |
| --- | --- | --- |
| Agent Card discovery | YES | Configured URL, validated card and endpoint selection |
| SendMessage | YES | Text, Data and File Part representation; Task **or** direct Message |
| GetTask | YES | Explicit remote polling by caller |
| ListTasks / CancelTask | YES | Scope to selected remote agent + authenticated identity |
| Authentication | YES | Application-supplied short-lived credential callback; no hardcoded tokens |
| HTTP safety / errors | YES | Release-blocking security requirements below |
| Client-only Rails use | YES | Do not require `config.agent` or local Task Store |
| SSE / SubscribeToTask | NO | Separate proposed streaming milestone |
| Push notifications, gRPC, REST binding | NO | Can add after JSONRPC v1.0 contract |
| Multi-agent planning / automatic polling | NO | Host application concern |
| Remote Task persistence or generated DB migrations | NO | Host may persist remote task references |

Avoid silently changing any existing `0.2.0` Server default, routes, authentication, or Task lifecycle.

## Proposed Rails API (subject to spike)

```ruby
# This API is a design sketch. It is NOT available in a2a-rails 0.2.0.
client = A2A::Rails::Client.new(
  agent_card_url: "https://translator.example/.well-known/agent-card.json",
  allowed_hosts: ["translator.example"],
  authorization: -> { "Bearer #{Rails.application.credentials.dig(:a2a, :translator_token)}" },
  open_timeout: 3,
  read_timeout: 10
)

card = client.agent_card  # SDK-independent Ruby data
result = client.send_message(
  message: {
    message_id: SecureRandom.uuid,
    role: "ROLE_USER",
    parts: [{ text: "Hello" }]
  }
)

case result.kind
when :task
  task_id = result.task.fetch(:id)
  # Later, in application code / an application-owned Job:
  task = client.get_task(id: task_id)
when :message
  message = result.message
end

page = client.list_tasks(context_id: "known-context")
client.cancel_task(id: "known-running-task")
```

API design rules:
- `message:` accepts a complete SDK-independent Ruby hash to avoid text-only coupling. A `send_text` convenience method can follow later; do not discard Data/File Parts.
- Inputs may accept `snake_case` symbol keys; the adapter converts to the exact A2A v1.0 wire shape, including `ROLE_USER`, message ID, and part fields.
- `SendResult#kind` is exactly `:task` or `:message`; normalized `task`/`message` are Ruby values, never SDK schema objects. `get_task` returns a normalized Task; `list_tasks` returns tasks and pagination token. Specify precise DTO shapes in the implementation contract before shipping.
- Remote task ID and context ID are **remote identifiers**, not references to this Gem's inbound ActiveRecord/Memory Task Store. Do not treat IDs as authorization.
- Calling `get_task` is not blocking-until-completion; `send_message` may return `SUBMITTED` or `WORKING`. `INPUT_REQUIRED` and `AUTH_REQUIRED` should remain visible states, not be flattened to success/failure, even though automated continuation is out of scope.
- Authentication credentials are supplied per client/target by the host. No Client token is placed in Agent Cards, logs, query strings, or DB records.
- Any application-controlled target must still pass outbound URL policy. Do not infer trust from a valid Agent Card alone.

## Discovery, v1.0 negotiation and outbound URL trust

1. The host passes an explicitly configured `agent_card_url`, not user-provided arbitrary URLs by default.
2. Validate scheme, origin/host allowlist, DNS/IP destination, certificate, response size and JSON content before and **at the actual connect**; do not follow redirects across trusted boundaries.
3. Fetch Agent Card at the configured URL; validate relevant required data and `supportedInterfaces[]`.
4. Walk ordered interfaces; select the **first permitted** `protocolBinding == "JSONRPC"` with `protocolVersion == "1.0"`. Ignore unsupported bindings; if none match, fail clearly.
5. Validate the declared JSON-RPC interface URL **again** (it can differ from the discovery host). Explicit authorization for any different origin is required; never automatically forward credentials.
6. When the selected interface declares a `tenant`, preserve it exactly according to the binding. Verify SDK 2.0.0 can represent this before enabling such targets; otherwise fail as unsupported.
7. Use the **declared interface URL**, not a guessed `/`, `/a2a` or `/rest`, and send the A2A v1.0 version/header behavior required by the protocol.
8. No fallback to A2A v0.3, gRPC or REST unless a future explicitly reviewed phase adds it.

Agent Card lookup and JSON-RPC transport must be separate concepts. SDK's `A2A::Client.new(url)` currently fetches a conventional well-known path relative to its base URL and invokes RPC via its Faraday connection; this does **not** establish that arbitrary `supportedInterfaces[].url` paths work. A real HTTP compatibility spike is mandatory.

## Security gates (must pass before enabling a production Client)

- **SSRF**: production HTTPS only by default; allowlisted domains/origins, validate resolved connect address, block loopback, link-local, RFC1918/ULA, cloud metadata and other non-public destinations unless an explicitly unsafe local-test mode is used. Mitigate DNS rebinding and proxy bypass; URL syntax checking alone is insufficient.
- **Redirects / credentials**: reject unexpected redirects; never send Authorization, cookies, or custom sensitive headers to an unapproved origin. Require server TLS validation. Treat card-declared RPC URLs as untrusted.
- **Timeouts and resource budget**: bounded connect/read/total deadlines, card/RPC response bytes, JSON depth and task/message sizes; no indefinite blocking. Exact public defaults are TBD after the spike.
- **Logging**: only agent identifier, operation, elapsed time, sanitized status and correlation ID; never message parts, Authorization headers, credential values, Agent Cards with private data, or raw response bodies. The SDK's `A2A::Client` currently invokes `Console.info` with request params. Do **not** rely on mutating process-global logging level during concurrent Rails requests.
- **Side effects / retries**: no automatic retries of `SendMessage` or `CancelTask`. A timeout may occur after successful remote execution. Callers own idempotency and reconciliation. Consider bounded idempotent GetTask retries only after explicit testing.
- **Identity / ownership**: caller supplies their credentials. Remote server enforces its own Task permissions; the Client must not assume the inbound Gem's principal scope applies to remote agents.
- **Error safety**: distinguish invalid local input/configuration, incompatible Agent Card, transport/timeout/TLS, authentication/authorization response, and remote A2A errors. Preserve safe error code/status without exposing untrusted server messages verbatim in logs.

If the SDK transport cannot enforce these controls safely, use a narrowly scoped custom transport **behind the outbound adapter** rather than relaxing the release gates.

## Proposed internal structure

```text
lib/a2a/rails/client.rb                   # public façade
lib/a2a/rails/client/agent_card_resolver.rb
lib/a2a/rails/client/outbound_policy.rb
lib/a2a/rails/client/send_result.rb
lib/a2a/rails/client/errors.rb
lib/a2a/rails/protocol/client_adapter.rb
lib/a2a/rails/protocol/agent2agent_client_adapter.rb
test/unit/client/
test/contract/agent2agent_client/
test/integration/client/
test/e2e/client/
```

A `Client` instance should be usable in a normal Rails service and in a host-owned ActiveJob. It must **not** require `A2A::Rails.configuration.agent`, local `Runtime` or `Task::Store`. For an application that only consumes other agents, define a Client-only opt-out from inbound HTTP route registration (e.g. `config.server_enabled = false`) while retaining current server-enabled behavior as the default for existing users. Treat any route/Engine changes as a separately reviewed compatibility slice.

## Errors and API boundary

Illustrative (names not final):
- `Client::ConfigurationError` — missing allowlist, invalid URL, incompatible interface.
- `Client::TransportError` / `Client::TimeoutError` — unreachable remote or timeout; never claim the operation did not execute.
- `Client::AuthenticationError` — remote authentication/authorization rejected.
- `Client::RemoteError` — remote A2A protocol error with sanitized code and operation.
- `Client::InvalidResponseError` — malformed/wrong-version/wrong-shaped or oversized response.

Do not reuse inbound `TaskNotFoundError` if it obscures that the error originated from another server. Do not leak `A2A::Protocol::JsonSchema::Definition`, Faraday or async-http objects in the public API.

## Step 29 follow-up execution plan

1. **29-1 — SDK / transport spike**: verify *published* `agent2agent 2.0.0`, actual discovery and `/a2a` routing, version headers, Faraday/Async use in plain Rails sync code, logging suppression strategy, auth/TLS/timeouts, and Task vs direct Message response mapping. Record red/green findings; no product API yet.
2. **29-2 — Public contract**: settle constructor defaults, DTO/error contracts, client-only mode, security policy; write tests and example before implementation.
3. **29-3 — Discovery + safe transport**: endpoint selection, SSRF/redirect/certificate and bounded I/O tests.
4. **29-4 — Core remote operations**: SendMessage/GetTask/ListTasks/CancelTask, normalized values, no hidden retries, unit/contract tests.
5. **29-5 — External HTTP integration**: published `a2a-rails-demo 0.2.0` at local-only test endpoint, and at least one independent Python/Go Agent Server; positive + negative security cases across supported Ruby/Rails CI matrix.
6. **29-6 — Documentation + version decision**: consumer usage, examples, changelog, roadmap, exact-artefact release verification in a separate explicitly approved release step.

## Completion criteria

- Public Rails code imports no `A2A::Client`/SDK schema types and can run without a server Agent configured.
- Card discovery selects an exact, compatible JSONRPC 1.0 URL; missing/incompatible/malicious URLs fail closed.
- Both direct Message and Task responses, non-terminal states, context/message IDs and rich parts survive normalization.
- Production security gates are verified with real HTTP tests, including redirects, private DNS, TLS, timeouts and log redaction.
- Remote task operations are authorized by remote credentials, never by local Task IDs alone.
- Supported Ruby/Rails matrix and independent interoperability tests pass.
- Server-facing `0.2.0` behavior remains backward compatible.
- No new release/tag/RubyGems publication is implied by completion of this design.

## Sources and current-code evidence

- [A2A v1.0 Agent Card / supportedInterfaces specification](https://a2a-protocol.org/v1.0.1/specification/)
- [agent2agent JSON-RPC Client documentation](https://general-intelligence-systems.github.io/agent2agent/client-json-rpc/)
- [agent2agent pinned-source Client implementation used in initial SDK spike](https://github.com/general-intelligence-systems/agent2agent/blob/273f45f6b7358b0b0e76bbc0dcf12395e3cc5963/lib/a2a/client.rb)
- [Step 15 compatibility spike](sdk-compatibility-spike.md)
- [Gem structure/SDK isolation](gem-structure.md)
- [Current roadmap](../../ROADMAP.md)

**Important**: This is a proposal, not a report of passing tests or implemented Client functionality. Security requirements and SDK integration details must be resolved empirically before the Client ships.
