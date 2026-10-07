# Step 16-1 — Security Threat Model & Integration Design (Historical Baseline)

Status: **initial 2026-10-07 design snapshot for published v0.1.0**. Steps 16-1–16-5 were subsequently implemented on the **unreleased main branch**. The proposed APIs and "open decisions" below are preserved as their original threat-model record; use the [current authentication guide](../guides/authentication.md) and [production review](../guides/production-security.md) for actual behavior.  
Tracking: [Security hardening issue #11](https://github.com/cuichangquan/a2a-rails/issues/11)  
Baseline: published `a2a-rails` v0.1.0 (2026-10-06)  
Target protocol: A2A v1.0 JSON-RPC over HTTP.

## 1. Scope / current state

The Gem serves:

- `GET /.well-known/agent-card.json` — metadata and endpoint discovery.
- `POST /a2a` — `SendMessage`, `GetTask`, `ListTasks`, `CancelTask`.

The engine controllers currently call `A2A::Rails.runtime` directly without built-in caller authentication. The runtime creates a request handler with a shared process-local `Task::MemoryStore`; `RequestHandler` performs Task operations without caller-aware ownership checks. A caller-supplied `contextId` is only a filter, not proof of authorization. The public Agent Card does not advertise authentication requirements.

**Therefore v0.1.0 should not be exposed as an unauthenticated production A2A endpoint.** Existing Rack / reverse-proxy / application controls may protect a specific deployment, but the Gem does not enforce or verify that protection.

## 2. Trust boundaries

```text
untrusted A2A client
      |
      | HTTPS + Authorization header (or mTLS at trusted gateway)
      v
trusted ingress / Rails authentication integration
      |
      | verified caller identity (principal_id, optional tenant)
      v
A2A engine authorization boundary
      |
      | allow/deny operation; enforce principal-scoped Task access
      v
Protocol Adapter -> RequestHandler -> Task Store -> Agent Handler
      |
      v
Rails application's business-specific authorization
```

The caller must not determine its own principal by sending `contextId`, `taskId`, `tenant`, arbitrary metadata, or unchecked identity headers. A task UUID is an identifier, **not an access token**.

## 3. Primary threats and proposed controls

| Threat | Evidence / entry point | Proposed control | Test |
| --- | --- | --- | --- |
| Unauthenticated Handler invocation | `POST /a2a` passes to SDK without authentication | Application-supplied authenticator; production fail closed when not configured | No credentials → 401; Handler never called |
| Cross-caller Task access | `GetTask` finds by ID | Scope by authenticated principal (optionally tenant) in Task Store / authorization layer | User B cannot read A's Task |
| Cross-caller Task enumeration | `ListTasks` without mandatory ownership predicate | Enforce principal predicate independent of optional filters; scope totals | User B sees no A tasks, even without `contextId` |
| Cross-caller Task cancellation | `CancelTask` finds by ID | Authorize before atomic state change | User B cannot cancel A's Task |
| Pagination data leakage | `MemoryStore` snapshot page tokens are not bound to caller | Bind snapshot to principal and query, or partition cursor storage | A's `pageToken` fails for B |
| Untrusted context / tenant | Client JSON `contextId`; `tenant` unsupported today | Never derive principal from payload; validate tenant routing against trusted identity | Forged context/tenant cannot cross boundaries |
| Sensitive request/environment logging | SDK had INFO Rack environment output | Keep focused SDK log suppression; inspect all auth/error logging | No Authorization header, tokens, or raw body leaked |
| Invalid/oversized payloads | SDK schema validation has documented coverage gaps | Length bounds + strict request checks before execution | Oversized/malformed requests rejected safely |
| Public Agent Card mismatch | Card currently does not declare auth | Advertise correct supported scheme and required `security` consistently with runtime behavior | Card accurately matches protected endpoint |
| Network abuse | Synchronous Handler and process-local store | HTTPS, proxy trust review, rate / concurrency limits, Task / cursor retention | Limit tests and deployment instructions |

## 4. Proposed authentication contract — not finalized

Keep the Gem neutral about identity providers (Devise, Doorkeeper, mTLS, external gateways). A Rails host integrates a **trusted verifier** at the request boundary; a mere presence check for an Authorization header is insufficient.

Illustrative configuration shape for review **(not an implemented API)**:

```ruby
A2A::Rails.configure do |config|
  config.agent = "EchoAgent"

  # Concept only; final signature and failure semantics are TBD.
  config.authenticate_request = ->(request) {
    principal = MyApp::A2AAuthenticator.call(request) # verifies credential
    # Return stable, non-secret principal / tenant identity if valid.
    principal
  }
end
```

Requirements for the final contract:

- Authenticator runs before parsing, SDK dispatch or executing Handlers.
- Missing / invalid credentials return a controlled HTTP 401 and suitable `WWW-Authenticate` challenge; authenticated but forbidden returns HTTP 403 (or the selected A2A binding's equivalent where appropriate).
- Stable principal identity comes from **server-verified** credentials, never from the A2A request body.
- Authorization policy can protect operations and application-specific actions (e.g. a purchase), not only Task ownership.
- Credentials are not persisted in Tasks or forwarded as `context` to generic Handlers.
- The implementation advertises supported A2A `securitySchemes` / `security` matching the configured authentication mechanism.
- Agent Card may remain public only when its metadata is safe to disclose; offer a documented option to restrict it when needed.

### Production default (proposal to decide)

Prefer **fail closed** for protected `POST /a2a` in production unless a valid authenticator/security boundary is configured. The exact strategy for existing v0.1.0 users, API naming, early Rails boot, and local development smoke tests needs an explicit compatibility decision before implementation. Do not silently change the published v0.1.0 behavior.

## 5. Task ownership enforcement

Principal scope must be enforced **inside the Task access boundary**, not by a best-effort optional controller filter.

Conceptual rules:

- `SendMessage`: persist the authenticated owner when creating a Task.
- `GetTask`: return Task only if caller is owner or policy explicitly grants access. Prefer not-found semantics for non-owned task IDs to reduce existence leakage.
- `ListTasks`: owner predicate is **always** applied before `contextId`, state and timestamp filters and pagination; counts and snapshots are scoped too.
- `CancelTask`: ownership check and state change must avoid a time-of-check / time-of-use race.
- `SendMessage` with `taskId`: authorize ownership **before** returning any error that reveals whether a foreign Task exists; continuation remains unsupported in v0.1.
- Pagination cursor: associate the cursor snapshot with the authenticated principal (and query fingerprint) or use independently scoped stores; tokens are unguessable but still must be access checked.
- Separate credentials belonging to the same permitted principal should be able to access the owner's Tasks; tokens themselves must not be used as ownership keys.
- Preserve Task wire schema: private owner metadata must not be leaked through `TaskMapper` or logs.

Potential approach: a principal-scoped Store / lifecycle boundary and a typed `Principal` context passed from controller to runtime to handler. Compare with an owner-aware shared store for concurrency, memory growth and authorization consistency **before choosing an implementation**.

## 6. Security review / regression matrix

Minimum tests for a follow-up PR:

1. Missing credentials, invalid credentials, revoked credential, verifier exception; no Handler invocation.
2. Public/private Agent Card policy and advertised security requirements.
3. A sends Task; A reads/lists/cancels; B cannot read/list/cancel.
4. B cannot reuse A's `contextId`, `taskId`, or `pageToken` to access A's Task.
5. `ListTasks` totals, filters and pagination are owner scoped.
6. Cancellation / completion races keep terminal state guarantees and owner checks.
7. No raw secrets, authorization headers, SDK exception details or Rack environment in public errors or INFO logs.
8. Demo Echo Quick Start stays reproducible under an explicit local-only security setting.
9. Tests exercise Rails HTTP endpoints (not just `RequestHandler` units).
10. Verify Ruby 3.3/3.4/4.0 × Rails 8.0/8.1 matrix and packaged Gem smoke.

## 7. Open design decisions for Step 16-2

- Choose the public authentication callback name and verified principal representation.
- Decide whether authentication is always required, or is explicit local-only bypass plus production fail-closed.
- Decide who authenticates an Agent Card and where security scheme metadata is configured.
- Define HTTP 401/403 response shape and challenge headers for the JSON-RPC binding.
- Choose ownership scoping architecture and how `ListTasks` page tokens bind to a caller.
- Document any compatibility impact, migration and intended patch/minor release.

## 8. References

- [A2A v1.0 specification](https://a2a-protocol.org/v1.0.0/specification/) — authentication/authorization, security schemes and scoped Task access.
- [Published v0.1.0 behavior](../../README.md)
- [Task semantics](../design/v0.1-decisions.md)
- [Tracking issue #11](https://github.com/cuichangquan/a2a-rails/issues/11)

**Historical note:** Step 16-1 originally recorded proposed behavior. The merged implementation is tracked in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) and [ROADMAP.md](../../ROADMAP.md); published RubyGems v0.1.0 remains unchanged.
