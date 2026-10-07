# Authenticating A2A HTTP requests — Step 16-2

> **Security status: In development.** This page describes changes proposed in Step 16-2. It does not apply to the already-published `a2a-rails 0.1.0`.
>
> **Not production-safe yet:** Step 16-2 authenticates requests, but it does **not** implement per-principal authorization for `GetTask`, `ListTasks`, `CancelTask`, or pagination. That is [Step 16-3](https://github.com/cuichangquan/a2a-rails/issues/11). Do not expose your A2A Task endpoint to untrusted clients.

## Goal

Use the host Rails application's verified identity system. a2a-rails does **not** issue credentials, verify OAuth tokens, or depend on Devise/Doorkeeper. Your application verifies credentials and returns the stable, **non-secret** caller ID to the Gem.

The authentication callback executes at the Rails `POST /a2a` controller, **before** the A2A SDK parses/dispatches requests.

## Configuration

Example host initializer (adapt the verifier to your own application):

```ruby
A2A::Rails.configure do |config|
  config.agent = "EchoAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]

  # Must verify signature/token validity, expiry, issuer, audience and relevant
  # scopes. The verifier below is application-owned; it is NOT provided by
  # a2a-rails.
  config.authenticate_request = lambda do |request|
    identity = MyApp::A2ATokenVerifier.verify(request.authorization)
    identity&.subject # stable, non-secret String such as "agent-client-42"
  end

  # Override when your verifier uses a different authentication mechanism.
  config.authentication_challenge = 'Bearer realm="a2a"'
end
```

### Callback contract

| Callback outcome | HTTP result |
| --- | --- |
| Returns a nonempty, non-control-character String (<= 256 bytes) | Request reaches the existing A2A endpoint |
| Returns `nil` or `false` | 401 Unauthorized; `WWW-Authenticate` challenge |
| Raises `A2A::Rails::Authentication::Forbidden` | 403 Forbidden |
| Raises any other exception, is not callable or returns an invalid type | 500 Authentication unavailable; generic response |

Callback receives an `ActionDispatch::Request` and must use a **trusted verifier**, not a header-presence check. Do not return credentials, bearer tokens, arbitrary names supplied by clients, or objects containing secrets. Returned IDs are stored in a request-local Rack environment entry for future Task scoping, not exposed as a public Handler API.

**Authentication is not authorization.** Even a successful identity check does not currently restrict Task access by owner. The host application must enforce its own business permissions separately.

### Missing callback behavior

- Rails `production` and any environment other than `development` / `test`: `POST /a2a` returns **401** (fail closed) if no callback is configured.
- Rails `development` and `test`: missing callback permits local Quick Start requests, preserving the published documentation. A callback, once configured, is enforced even in these environments.
- Never expose the development/test fallback to untrusted networks; Rails environment names alone do not prove a request is local.
- `GET /.well-known/agent-card.json` remains public in Step 16-2; only the A2A Task endpoint is gated.

### HTTP response behavior

Unauthorized calls receive 401 and a configurable `WWW-Authenticate` challenge (default `Bearer realm="a2a"`); explicit policy denials receive 403. Callback failures do not echo exception messages. The A2A HTTP endpoint sets `Cache-Control: no-store` to avoid caching sensitive Task content.

The error is an HTTP boundary response, not an A2A task or a promise of a JSON-RPC result. Authorization is performed before the SDK has parsed the JSON-RPC request ID.

## What is NOT implemented in Step 16-2

- Task ownership checks and tenant isolation.
- Binding Task List pagination cursors to an authenticated principal.
- Agent Card `securitySchemes` / `security` advertising or selective Agent Card visibility.
- Rate limiting, body-size limits and end-to-end production deployment hardening.
- OAuth authorization server, token introspection, mTLS termination or a token issuer.

These remain tracked in [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11). Security review and integration tests must be completed before a public-production deployment can be considered safe.

## Verification

- Unit tests for fail-closed behavior, missing/invalid credentials, principal integrity, challenge safety and explicit forbidden results.
- Rails HTTP smoke tests for 401/403/200 and a sanitized 500 verifier failure.
- Existing published Echo Quick Start and Gem package smoke tests should continue to pass.

See also: [Roadmap](../../ROADMAP.md), [Security Threat Model draft (PR #12)](https://github.com/cuichangquan/a2a-rails/pull/12).
