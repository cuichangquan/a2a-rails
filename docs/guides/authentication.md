# Authenticating and scoping A2A HTTP requests — Steps 16-2 / 16-3

> **Security status: implemented on the unreleased `main` branch.** These changes do **not** apply to the already-published `a2a-rails 0.1.0`.
>
> **Not production-safe yet:** Steps 16-2 and 16-3 were merged into `main` via [PR #13](https://github.com/cuichangquan/a2a-rails/pull/13) and [PR #15](https://github.com/cuichangquan/a2a-rails/pull/15), but are not released. Agent Card security advertisement, payload/abuse controls, application-specific authorization and a complete security review remain outstanding in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11). Do not expose your A2A Task endpoint to untrusted clients.

## Goal

Use the host Rails application's verified identity system. a2a-rails does **not** issue credentials, verify OAuth tokens, or depend on Devise/Doorkeeper. Your application verifies credentials and returns the stable, **non-secret** caller ID to the Gem.

The authentication callback executes at the Rails `POST /a2a` controller, **before** the A2A SDK parses/dispatches requests.

## Configuration

Example host initializer (adapt the verifier to your own application):

```ruby
A2A::Rails.configure do |config|
  config.agent = "EchoAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]

  # Step 16-5: declare the same Bearer security profile that the host
  # application actually enforces. The Gem does not mint or verify tokens.
  config.security_schemes = {
    "bearer" => {
      "httpAuthSecurityScheme" => {
        "scheme" => "Bearer",
        "bearerFormat" => "JWT"
      }
    }
  }
  config.security_requirements = [
    { "schemes" => { "bearer" => { "list" => [] } } }
  ]

  # Must verify token validity, expiry, issuer, audience and relevant
  # application permissions. The verifier below is application-owned.
  config.authenticate_request = lambda do |request|
    identity = MyApp::A2ATokenVerifier.verify(request.authorization)
    identity&.subject # stable, non-secret String such as "agent-client-42"
  end

  config.authentication_challenge = 'Bearer realm="a2a"'
end
```

The public Agent Card now advertises A2A v1.0 `securitySchemes` and `securityRequirements` that correspond to the configured verifier. A verifier without matching security metadata is rejected, and production/staging Agent Cards fail closed instead of looking unauthenticated. Step 16-5 intentionally supports the HTTP Bearer profile only; do not advertise API-key, OAuth2, OIDC or mTLS profiles until those host integrations are implemented and tested.

### Callback contract

| Callback outcome | HTTP result |
| --- | --- |
| Returns a nonempty, non-control-character String (<= 256 bytes) | Request reaches the existing A2A endpoint |
| Returns `nil` or `false` | 401 Unauthorized; `WWW-Authenticate` challenge |
| Raises `A2A::Rails::Authentication::Forbidden` | 403 Forbidden |
| Raises any other exception, is not callable or returns an invalid type | 500 Authentication unavailable; generic response |

Callback receives an `ActionDispatch::Request` and must use a **trusted verifier**, not a header-presence check. Do not return credentials, bearer tokens, arbitrary names supplied by clients, or objects containing secrets. Returned IDs are stored in a request-local Rack environment entry for future Task scoping, not exposed as a public Handler API.

**Authentication is not authorization.** Step 16-3 enforces owner checks for Task operations on `main`, but the host application must still authorize application-specific business actions. For multi-tenant apps, the host verifier must return a globally unique, tenant-qualified principal ID. Two different tenants must never share the same principal identifier.

### Missing callback behavior

- Rails `production` and any environment other than `development` / `test`: `POST /a2a` returns **401** (fail closed) if no callback is configured.
- Rails `development` and `test`: missing callback permits local Quick Start requests, preserving the published documentation. A callback, once configured, is enforced even in these environments.
- Never expose the development/test fallback to untrusted networks; Rails environment names alone do not prove a request is local.
- `GET /.well-known/agent-card.json` remains public in Step 16-2; only the A2A Task endpoint is gated.

### HTTP response behavior

Unauthorized calls receive 401 and a configurable `WWW-Authenticate` challenge (default `Bearer realm="a2a"`); explicit policy denials receive 403. Callback failures do not echo exception messages. The A2A HTTP endpoint sets `Cache-Control: no-store` to avoid caching sensitive Task content.

The error is an HTTP boundary response, not an A2A task or a promise of a JSON-RPC result. Authorization is performed before the SDK has parsed the JSON-RPC request ID.

## Step 16-3 Task ownership (implemented on main; unreleased)

- The trusted, verified principal ID flows from the Rails authentication gate through Runtime to a per-request Task Lifecycle.
- Newly created Tasks persist a private `owner_id`, which is never included in the A2A Task wire schema.
- `GetTask`, `CancelTask`, and attempted Task continuation return Task-not-found for another principal's Tasks.
- `ListTasks`, total counts, and filtered results are always scoped by owner; page tokens are bound to the principal and query fingerprint.
- Existing local-only, unauthenticated Quick Start Tasks remain scoped to the anonymous `nil` principal. Such Tasks are not readable by authenticated principals.
- Task state transitions check ownership under the Memory Store mutex, avoiding cancellation authorization races.

## What is NOT implemented in Steps 16-2 / 16-3

- A built-in identity provider, tenant resolver, or business-action authorization policy.
- General-purpose per-tenant Task sharing or delegated Task permissions.
- Agent Card `securitySchemes` / `security` advertising or selective Agent Card visibility.
- Distributed rate limiting and end-to-end production deployment hardening. [Step 16-4 request hardening](request-hardening.md) provides bounded HTTP bodies and additional input checks on the unreleased main branch, but does not provide a distributed rate limiter.
- OAuth authorization server, token introspection, mTLS termination or a token issuer.

These remain tracked in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11). Security review and integration tests must be completed before a public-production deployment can be considered safe.

## Verification

- Unit tests for fail-closed behavior, missing/invalid credentials, principal integrity, challenge safety and explicit forbidden results.
- Ownership tests for find/list/count/cursor/cancel/transition across authenticated and anonymous callers.
- Real Rails HTTP smoke tests for 401/403/200, a sanitized 500 verifier failure, and cross-principal access denial.
- Existing Echo Quick Start and Gem package smoke tests passed the CI matrix for PR #15.

See also: [Roadmap](../../ROADMAP.md), [Security Threat Model](../design/security-threat-model.md).
