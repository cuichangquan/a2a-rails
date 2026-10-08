# Step 29-1 — Ruby SDK Outbound Client Compatibility Spike

> **Status:** execution pending; reproduce with [GitHub Actions workflow](../../.github/workflows/a2a-client-spike.yml).  
> Tracking: [Issue #75](https://github.com/cuichangquan/a2a-rails/issues/75); proposed Client API remains separate in [Step 29 design PR #76](https://github.com/cuichangquan/a2a-rails/pull/76).  
> This is **a test-only spike**, not a new A2A Client API nor a production-grade HTTP integration.

## Scope and exact versions

- Client: Ruby SDK `agent2agent = 2.0.0` (`A2A::Client`), which is already a transitive dependency of the demo Gem.
- Remote Server: independent [a2a-rails-demo](https://github.com/cuichangquan/a2a-rails-demo) at **`7cb002a63d6cc976b1562ee45e8a260771d7ef1d`**.
- Server dependency: **published RubyGems `a2a-rails = 0.2.0`**, verified via Bundler source inspection; not a local Gem checkout.
- Ruby 3.4.10, Rails 8.1.0, loopback `127.0.0.1:3000`. No public network listener and no real credentials.
- A2A wire: JSONRPC v1.0, Agent Card at `/.well-known/agent-card.json`, interface declared in `supportedInterfaces[]`.

## Reproduction

From repo checkout, use the [workflow](../../.github/workflows/a2a-client-spike.yml) or start the published [Demo](https://github.com/cuichangquan/a2a-rails-demo) on loopback, then from its Bundler environment:

```sh
cd /path/to/a2a-rails-demo
bundle exec ruby /path/to/a2a-rails/spikes/a2a_client_v03/client_probe.rb
```

The client probe is at [`spikes/a2a_client_v03/client_probe.rb`](../../spikes/a2a_client_v03/client_probe.rb).

## Checks executed by the probe

1. Verify published SDK 2.0.0 and published Gem 0.2.0.
2. Fetch Agent Card using raw HTTP and the SDK `agent_card` method.
3. Read a matching `JSONRPC`/`1.0` entry and use its **exact declared endpoint** (`/a2a`), rather than guessing `/`.
4. Send text with explicit `A2A-Version: 1.0`; verify completed Task plus Echo artifact.
5. Verify GetTask, ListTasks, and direct Message return shape.
6. Verify terminal CancelTask raises a typed SDK JSON-RPC error.
7. Probe SDK no-header/default version behavior. Record its real outcome rather than presuming success.
8. Use Faraday test adapter to confirm host-supplied `Authorization` and `A2A-Version` request headers and timeout options (fake token only).

All failure paths fail the CI job. The no-header control is deliberately informational, as it is implementation-specific and not itself a conformance requirement.

## Known source-level risks (not yet closed by this smoke)

- SDK `A2A::Client` builds the well-known Agent Card URL relative to its configured base, but protocol RPC is sent to the configured connection endpoint. Discovery base and interface endpoint need separate management. Source: [pinned SDK Client implementation](https://github.com/general-intelligence-systems/agent2agent/blob/273f45f6b7358b0b0e76bbc0dcf12395e3cc5963/lib/a2a/client.rb).
- SDK calls `Console.info(self) { "Client #{op.name}: #{params}" }`: messages/parts may be written to logs. **Blocking privacy/security concern** before production rollout.
- Header and timeout injection through Faraday is **not** equivalent to an SSRF-safe transport. TLS validation, resolved-address filtering, DNS rebinding, redirect policy, proxy bypass, size limits and cross-origin credential boundaries are **not** verified by this probe.
- Remote Task IDs are not local Task Store keys. Remote permission checks belong to the remote server.
- No production authentication integration, secret management, cancellation reconciliation or safe retry policy is implemented.
- No streaming/SSE, push notifications, REST or gRPC tested.

## Decision after execution

- Record exact run URL, number of completed checks, deviations and observed SDK limitations here.
- If core SDK transport works, proceed to **Step 29-2** public API/DTO contract plus safe outbound policy design before any implementation.
- If SDK path/version/logging cannot be configured safely, keep these shortcomings behind an outbound `Protocol::ClientAdapter` and prototype a constrained HTTP transport in a dedicated follow-up spike.
- Do not merge or publish a new Gem version based solely on these results.
