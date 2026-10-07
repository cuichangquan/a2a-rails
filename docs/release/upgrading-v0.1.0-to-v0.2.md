# Upgrading from a2a-rails v0.1.0 to the proposed v0.2 line

> The v0.2 line is **not released yet**. This guide describes current unreleased main and the working `v0.2.0-rc.1` plan. Keep using the actual published v0.1.0 documentation unless you intentionally test source main.

## Why this is not treated as a patch-only upgrade

The current main branch retains the same server-first JSON-RPC v1.0 direction, but it changes important production behavior:

- production/staging A2A requests fail closed without a host authenticator;
- public Agent Card security metadata must match the configured Bearer verifier;
- Task read/list/cancel/pagination operations are scoped to the verified principal;
- invalid content types, oversized bodies and malformed inputs are rejected earlier;
- direct Message and File Artifact outputs add new opt-in capabilities.

Applications that previously exposed v0.1.0 without authentication can therefore stop working in production after upgrading until security configuration is supplied. That is intentional.

## 1. Keep local development simple

Development/test may omit the authenticator for localhost experimentation. Do not expose that fallback to a LAN or public ingress.

The standalone [a2a-rails-demo](https://github.com/cuichangquan/a2a-rails-demo) shows the intended local-only pattern and explicitly refuses production mode.

## 2. Configure production authentication and matching Agent Card metadata

The host Rails application verifies credentials. a2a-rails does not issue or introspect tokens for you.

Example shape:

```ruby
A2A::Rails.configure do |config|
  config.agent = "MyAgent"
  config.public_base_url = "https://agent.example.com"

  config.authenticate_request = lambda do |request|
    identity = MyApp::A2ATokenVerifier.verify(request.authorization)
    identity&.subject
  end

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
end
```

The returned principal ID must be stable, non-secret and tenant-qualified when needed. A bearer token itself must never be used as the stored owner ID.

## 3. Add application business authorization

Authentication only answers who the caller is. Each Handler remains responsible for whether that caller may perform the requested business action.

Do not use `taskId`, `contextId`, `messageId` or arbitrary client metadata as proof of authorization.

## 4. Understand Task isolation

Tasks created by one authenticated principal are not visible/listable/cancelable by another principal. Anonymous local Tasks are separate from authenticated Tasks.

If your v0.1.0 application assumed one shared process-wide Task namespace, update those assumptions and tests.

## 5. Account for stricter HTTP handling

Current main rejects unsupported content types, compressed A2A request bodies, oversized request bodies and malformed fields at the Rails HTTP boundary.

If a reverse proxy transforms or compresses inbound A2A requests, verify the complete deployed request path.

## 6. New optional output capabilities

### Direct Message

Task remains the default SendMessage result. A host Agent may opt into `response_mode :message` or a host-controlled callable. Direct replies do not create Task records.

### File Artifact

Handlers may explicitly return `A2A::Rails::FileArtifact.bytes` or `.url` for output File Parts. URL outputs are references; the Gem does not download arbitrary remote URLs for the application.

## 7. Production limitations remain

The default MemoryStore is still process-local and non-durable. A new release does not automatically make it suitable for public multi-worker production. Before accepting untrusted traffic, review:

- real token issuer/audience/revocation policy;
- business authorization;
- TLS, trusted proxies and host allowlisting;
- distributed rate/concurrency/cost limits;
- secret/log scrubbing;
- durable Task storage and retention policy;
- Handler side effects, idempotency and execution budgets.

See [Production security](../guides/production-security.md).

## 8. Release status

Until an actual candidate is versioned, built and approved:

- RubyGems latest remains **0.1.0**;
- source main is **unreleased**;
- no tag named `v0.2.0-rc.1` should be assumed to exist;
- do not report the source-only features as present in v0.1.0.

See [v0.2.0-rc.1 preparation decision](v0.2.0-rc.1-preparation.md).
