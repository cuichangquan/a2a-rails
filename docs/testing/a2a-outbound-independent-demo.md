# Step 29-5a — Independent published-Gem Demo outbound HTTPS smoke

> **Status: integration evidence only, not production release approval.**
> Tracks [Step 29-5 #87](https://github.com/cuichangquan/a2a-rails/issues/87) and [Step 29 #75](https://github.com/cuichangquan/a2a-rails/issues/75).
>
> Client source: current a2a-rails branch. Server: independent `cuichangquan/a2a-rails-demo` at pinned commit `7cb002a63d6cc976b1562ee45e8a260771d7ef1d`, bundled with **published RubyGems `a2a-rails 0.2.0`**, not a Git source or monorepo server.

## Why a TLS bridge is needed

The independent Demo intentionally binds to `127.0.0.1`, advertises `http://127.0.0.1:3000/a2a`, and refuses production/staging operation. The new outbound Client intentionally rejects HTTP, loopback and private-address DNS. Weakening production URL/SSRF checks to run a local smoke would be a security regression.

CI therefore:

1. Starts the pinned Demo over **loopback HTTP** as an independent process, with `BUNDLE_GEMFILE` pointing to its own Gemfile and a strict RubyGems-source/version assertion.
2. Creates a short-lived, **test-only** self-signed certificate for `echo-agent.test` and launches a local TLS bridge on loopback port 3443.
3. The bridge forwards requests to the independent Demo verbatim at the JSON-RPC layer, but **rewrites the Agent Card's advertised JSONRPC 1.0 interface URL to `https://echo-agent.test:3443/a2a`**. This deviation from the published raw Agent Card is essential and must not be misrepresented as a native HTTPS deployment.
4. Creates `A2A::Rails::Client.new` from the source checkout. Verifies that the **normal production policy refuses** the local test-only target, then uses a **test-only injected internal policy** that preserves exact HTTPS allowlist/origin and connects `echo-agent.test` to `127.0.0.1` for a *real TLS socket* with CA and SNI/hostname checks.
5. Exercises the public methods through real network I/O: Agent Card discovery, SendMessage → completed Task, remote Artifact text, GetTask, ListTasks, SendMessage → direct Message, terminal CancelTask numeric JSON-RPC error.
6. Cleans up the server and TLS bridge. No external third-party service or secrets are required.

## What this demonstrates — and what it does not

**Demonstrates:** current source Client API and its real pinned-IP TLS socket transport work against an independently released A2A server using published RubyGems 0.2.0, with correct `A2A-Version: 1.0`, JSON-RPC envelopes, Task and direct Message, pagination, and error code mapping.

**Does not demonstrate:**
- A production public-DNS HTTPS endpoint, production trust/egress architecture, or end-to-end no-injection use of the public Client constructor. The test injects an internal policy solely because it uses loopback, and sets a test CA. Production defaults still block local/private IPs.
- Unmodified remote Agent Card; only its JSONRPC interface URL is rewritten for HTTPS testing. Other card fields and all RPC payloads remain from the independent Demo.
- Python/Go **servers** reached by the new outbound Client; the previous Python/Go tests run clients against the existing Rails **inbound Server**, a different direction.
- Tenant authentication/authorization, rate limits, global egress controls, non-terminal Task flows, request idempotency across network errors or robust operation under concurrent jobs.
- Permission to release a new Gem. Current stable remains **0.2.0**, without the outbound Client.

## Verification and reproducibility

See [dedicated GitHub Actions workflow](../../.github/workflows/a2a-outbound-published-demo.yml), [Ruby Client probe](../../spikes/a2a_client_v03/independent_demo_outbound_probe.rb) and [TLS bridge](../../spikes/a2a_client_v03/independent_demo_https_bridge.py). Run the workflow to verify evidence for the exact PR head SHA.

Do not run the TLS bridge outside an isolated test machine. Do not expose the test server, inject the test policy through public app configuration, or skip TLS peer/hostname checks.
