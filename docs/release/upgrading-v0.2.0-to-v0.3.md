# v0.2.0 → v0.3.0 upgrade guide (stable release preparation / 正式版準備)

> **2026-10-10 status:** Stable `a2a-rails 0.3.0` is **not released**. The Step 31-5 candidate branch has an actual `VERSION = "0.3.0"`, but the Gem exists only as a private CI artifact until separate publication approval.  This is a review-ready guide for the planned stable version, based on **published prerelease `0.3.0.rc1`** and current main. It is **not** installation or deployment approval. Do not use unqualified `bundle update` to imply a stable `0.3.0` Gem exists. [Step 31 readiness](v0.3.0-stable-readiness.md) · [Step 31-4 feedback](v0.3.0-rc1-feedback-and-upgrade-readiness.md).

## What changes from published stable 0.2.0?

| Area | Existing 0.2.0 | Published 0.3.0.rc1 / planned 0.3.0 |
| --- | --- | --- |
| Rails A2A Server | Default-enabled Engine, Agent/Skill, Task/direct Message, auth, optional AR Store and ActiveJob | **Retained**; `server_enabled=true` remains the default |
| Outbound A2A Client | Not shipped | New `A2A::Rails::Client`: Agent Card discovery; A2A v1.0 JSON-RPC SendMessage, GetTask, ListTasks, CancelTask |
| Client-only host | No opt-out setting | `config.server_enabled = false` avoids inbound A2A routes and the need for `config.agent` |
| Security transport | Server-side auth and business authorization delegated to host | Client requires explicit HTTPS origins, checks all DNS answers, pins allowed public IPv4, verifies TLS hostname/CA, refuses redirects/proxy bypass, bounds size/time |
| Versions | Ruby >=3.3; Rails >=8.0,<8.2 | Same declared range; Ruby 3.3/3.4/4.0 × Rails 8.0/8.1 checked in RC1 CI |

**Not a v0.1.0→0.2.0 guide:** users upgrading from 0.1.0 must **first** review the [0.1→0.2 security/Task migration guide](upgrading-v0.1.0-to-v0.2.md). The 0.2.0 Server already fails closed for missing production authentication.

## 1. Safely test published RC1 (opt-in)

For a **test or explicitly approved evaluation Rails app** only:

```ruby
# Gemfile
gem "a2a-rails", "= 0.3.0.rc1"
```

```bash
bundle install
bundle exec ruby -ra2a-rails -e 'puts A2A::Rails::VERSION'
# Expected: 0.3.0.rc1
```

Stable 0.2.0 continues to be the default choice for users not adopting prerelease Client functionality. **Once stable `0.3.0` actually ships and passes its fresh artifact verification**, deliberately replace the Gemfile pin with `gem "a2a-rails", "= 0.3.0"` and re-run the application's CI and security tests. The stable version must not be installed or advertised as currently available.

## 2. Existing Server applications: no Client configuration required

Keep the existing host Agent/Skill/Handler setup. The new toggle defaults to Server-enabled:

```ruby
A2A::Rails.configure do |config|
  config.agent = "MyAgent"
  # Default: config.server_enabled = true
  # Keep existing authenticate_request/security_schemes/Task Store settings.
end
```

Do **not** change the Agent Card authentication metadata, Task ownership, migration or retention policy merely to get outbound Client functionality. Continue regression testing:

- Agent Card and JSON-RPC route still mounted, under the correct production auth/authorization.
- Inbound SendMessage **Task or direct Message**, GetTask/ListTasks/CancelTask.
- Any ActiveRecord Task Store (migration, persisted Task ownership, signed cursor, retention/prune) and ActiveJob/Solid Queue/Sidekiq asynchronous execution.
- Production host startup with the real verifier (no anonymous/public test fallback).

There is **no new mandatory database migration introduced by the outbound Client**. Existing v0.2.0 applications must preserve their own migration history and configured task-store settings.

## 3. Client-only Rails application: explicitly disable inbound routes

```ruby
# config/initializers/a2a_rails.rb
A2A::Rails.configure do |config|
  config.server_enabled = false
end
```

No `config.agent` is required. Check that both `GET /.well-known/agent-card.json` and `POST /a2a` return **404** for the Client-only host. Do not copy insecure local echo Server defaults into a public deployment.

## 4. Make an outbound request with exact, approved HTTPS origins

Use a real approved **public-DNS/public-IPv4, CA-valid HTTPS** Agent in a controlled environment; the following hostname is a non-live placeholder. The remote Agent Card determines the JSONRPC endpoint; its origin can differ from the Card origin, and that additional origin must be separately allowlisted.

```ruby
require "securerandom"

client = A2A::Rails::Client.new(
  agent_card_url: "https://agent.example.com/.well-known/agent-card.json",
  allowed_origins: ["https://agent.example.com"],
  authorization: -> { "Bearer #{ENV.fetch('A2A_RPC_TOKEN')}" },
  credential_origin: "https://agent.example.com",
  open_timeout: 3,
  read_timeout: 10,
  total_timeout: 15
)

result = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ text: "Hello" }]
})
case result.kind
when :task
  task = client.get_task(id: result.task.fetch(:id), history_length: 0)
when :message
  direct_message = result.message
end
```

For protected Agent Card discovery, also supply **separate** `card_authorization:` and `card_credential_origin:`, not an unscoped global token. If the Card advertises a different approved RPC origin, add that exact HTTPS origin to `allowed_origins:` and bind `credential_origin:` explicitly. Do not forward Card credentials to RPC automatically.

**Important:** the Gem's constructor has compatibility behavior for same-origin RPC credential defaults; the **recommended host practice** is always to specify the exact authorized RPC `credential_origin:`. The independent [Rails Client demo](https://github.com/cuichangquan/a2a-rails-client-demo) deliberately requires credentials and explicit origin together in its sample factory; that additional check lives in the **demo**, not a claim that every Gem constructor call requires both.

The Client does **not** automatically retry ambiguous `SendMessage`/`CancelTask` network timeouts. If a timeout reports `may_have_executed`, reconcile with remote Task state and your business idempotency policy before any explicit retry. Do not enqueue bearer tokens, raw Part bodies, a Client instance or credential callbacks in ActiveJob arguments; log safe opaque IDs only.

## 5. Expected API shapes / known limits

- `send_message` returns a `SendResult` with **either** `kind == :task` or `kind == :message`; never assume every reply has a Task ID.
- `agent_card`, `get_task`, `cancel_task` expose deeply frozen, normalized plain Ruby structures; `list_tasks` exposes a `ListResult` with tasks, cursor and counts. Remote custom Data/metadata extension keys are opaque.
- The Client deliberately **does not** fetch URL File Parts, auto-poll, auto-retry, orchestrate jobs or implement a production token issuer/tenant authorization.
- **Not supported:** IPv6-only Agent targets, streaming/SSE, push notifications and gRPC. A2A v1.0 JSON-RPC only.
- `MemoryStore` remains process-local by default; opt in to `ActiveRecordStore` for durable distributed Server Task state, and select a durable queue where appropriate.
- Public/no-auth production operation is **separately NO-GO by default**, per [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11). Publishing the Gem does not approve a host's exposure.

## Dependency advisory differences from RC1

The unpublished stable candidate raises `json` (a2a-rails's direct runtime dependency) to **`>= 2.19.9, < 3`**, following RubySec advisories for earlier JSON versions discovered during exact host testing. **Before adopting the candidate**, ensure your Ruby, Rails and existing Bundler lockfile can resolve this range. Do not bypass the bound to make an old application boot.

A full `gem "rails"` installation also installs `net-imap` through mail features. Initial independent Rails-host security checks found vulnerable `net-imap 0.4.25`; a candidate test host now uses patched `net-imap ~>0.5.15`. This is **not a new a2a-rails Gem dependency**: production users must update/audit **their own application's** `net-imap` and lockfile, not assume a RubyGem version bump repairs unrelated Rails/mail advisories.

See [candidate security finding details](v0.3.0-stable-candidate-record.md). The first failed candidate checks remain public, and successful remediated verification is a precondition for final release GO.

## 6. Regression checks before any version upgrade

1. Review the exact release bytes, Gem version, changelog and RubyGems provenance. `0.3.0.rc1` and future `0.3.0` are **different immutable artifacts**, and the RC1 SHA256 must never be reused for stable.
2. Run your Rails 8.0/8.1 test suite in the exact Ruby/Gemfile.lock host. Follow real principal authorization, log-filtering and TLS/egress decisions.
3. For Client-only hosts, assert inbound routes are absent; for Server hosts, assert authenticated inbound routes still work.
4. Test Task and direct Message replies, error handling, unknown Task states, and a timeout after which remote business effects might have occurred.
5. If queue workers and PostgreSQL are used, verify migration, persistence, crash/restart semantics, cancellation, retention and prune behavior. Gem CI does not replace the deployed app's operational tests.
6. Check the **actual** resolved dependency graph and security advisories in your app, not just Gem source or RC1's historical clean scan.
7. Review [the published RC1 integration evidence](v0.3.0-interop-advisory-evidence.md) and [Step 31 acceptance review](v0.3.0-client-security-api-review.md). Their isolated TLS and TCK limitations remain.

## 7. Reporting feedback

For non-security issues, use the [RC1 feedback issue template](https://github.com/cuichangquan/a2a-rails/issues/new?template=rc1-feedback.md), state the exact Gem/Ruby/Rails versions and a **sanitized** reproduction. For a suspected vulnerability, **do not post an exploit or secret in a public Issue**; follow [SECURITY.md](../../SECURITY.md).

**Release status:** stable 0.3.0 requires a separate frozen-version candidate, fresh SHA256, installed-artifact CI, dependency review and explicit maintainer publication authorization. This document itself does not authorize version changes, tag creation or Gem publishing.
