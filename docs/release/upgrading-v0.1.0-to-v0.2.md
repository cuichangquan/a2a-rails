# Upgrading from a2a-rails v0.1.0 to the proposed v0.2 line

> The v0.2 line is **not released yet**. Current main now includes Step 21 runtime changes after the historical `0.2.0.rc1` verification, so there is **no current approved release candidate**. Keep using the published v0.1.0 documentation unless you intentionally test source main.

## Why this is not treated as a patch-only upgrade

The current main branch retains the same server-first JSON-RPC v1.0 direction, but it changes important production behavior:

- production/staging A2A requests fail closed without a host authenticator;
- public Agent Card security metadata must match the configured Bearer verifier;
- Task read/list/cancel/pagination operations are scoped to the verified principal;
- invalid content types, oversized bodies and malformed inputs are rejected earlier;
- direct Message and File Artifact outputs add new opt-in capabilities;
- an optional ActiveRecord Task Store adds restart-safe/multi-worker persistence, retention and maintenance controls.

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

## 5. Choose Task storage deliberately

MemoryStore remains the default and is appropriate for local development or single-process experiments. It is not restart-safe and is not shared across Rails workers.

For durable Task state on current unreleased main:

```bash
bin/rails generate a2a:rails:task_store
bin/rails db:migrate
```

Then configure:

```ruby
A2A::Rails.configure do |config|
  # other configuration...
  config.task_store = :active_record
end
```

ActiveRecordStore is optional; applications that keep MemoryStore are not forced to load ActiveRecord through a2a-rails.

Default ActiveRecord maintenance policy:

```ruby
config.task_retention = 30.days
config.task_prune_batch_size = 1_000
config.max_tasks_per_owner = 10_000
config.max_task_history_entries = 100
config.max_task_artifacts = 50
```

Schedule bounded cleanup using:

```bash
bin/rails a2a:rails:tasks:prune
```

See [ActiveRecord Task Store](../guides/active-record-task-store.md). The per-owner count is a resource guard, not a billing-grade strict quota.

## 6. Account for stricter HTTP handling

Current main rejects unsupported content types, compressed A2A request bodies, oversized request bodies and malformed fields at the Rails HTTP boundary.

If a reverse proxy transforms or compresses inbound A2A requests, verify the complete deployed request path.

## 7. New optional output capabilities

### Direct Message

Task remains the default SendMessage result. A host Agent may opt into `response_mode :message` or a host-controlled callable. Direct replies do not create Task records.

### File Artifact

Handlers may explicitly return `A2A::Rails::FileArtifact.bytes` or `.url` for output File Parts. URL outputs are references; the Gem does not download arbitrary remote URLs for the application.

## 8. Production limitations remain

The default MemoryStore is still process-local and non-durable. ActiveRecordStore removes that persistence limitation when explicitly configured, but a new release still does not automatically make an endpoint suitable for public production. Before accepting untrusted traffic, review:

- real token issuer/audience/revocation policy;
- business authorization;
- TLS, trusted proxies and host allowlisting;
- distributed rate/concurrency/cost limits;
- secret/log scrubbing;
- actual durable Task Store selection, migration, retention/prune policy and database operation;
- Handler side effects, idempotency and execution budgets.

See [Production security](../guides/production-security.md).

## 9. Release status

Until a **new post-Step-21 candidate** is versioned, built and approved:

- RubyGems latest remains **0.1.0**;
- source main is **unreleased**;
- the historical `0.2.0.rc1` verification must not be used as publication evidence for current main;
- a new candidate must rerun artifact, PostgreSQL, security, Python/Go and TCK verification;
- do not report source-only features as present in v0.1.0.

See the [current release/deployment checklist](security-hardening-release-checklist.md).
