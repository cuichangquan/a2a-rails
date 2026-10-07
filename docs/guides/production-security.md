# Production security and deployment review (Step 16-6)

> **Deployment verdict as of 2026-10-07: NO-GO for open, untrusted production traffic.**
>
> Security changes from Steps 16-1–16-5 exist on the **unreleased `main` branch**, not in the published RubyGems **v0.1.0** artifact. A passed CI matrix and an authentication hook are not sufficient to call a public deployment secure.

This guide distinguishes what **a2a-rails enforces** from what the **host Rails application and ingress must enforce**. Use it before accepting any external A2A client connections. See [Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) and the [security review checklist](../release/security-hardening-release-checklist.md).

## Deployment suitability

| Use case | Status | Explanation |
| --- | --- | --- |
| Local Echo Quick Start in Rails development/test | Supported for local experimentation | Authenticator may be omitted in development/test. **Do not expose this bypass to a network.** |
| Isolated single-process staging with trusted test clients | Conditional, reviewed experiment only | Host authenticator + business policy, TLS, ingress restrictions, quotas, monitoring and documented restart consequences required. |
| Public Internet / untrusted clients | **NO-GO by default** | ActiveRecordStore now provides a durable option, but distributed rate limiting, execution budgets, real verifier/business policy and deployment-specific hardening are still required. |
| Multiple workers, replicas, or restart-resilient Task queries | **NO-GO with default MemoryStore; durable option available** | Configure the Step 21 ActiveRecordStore and run its migration/maintenance policy. PostgreSQL 16 durability and row-locking smoke is green, but the host deployment must still be reviewed. |

Passing the checks below can inform a **deployment-specific risk decision**, not a global production-ready statement about the Gem.

## 1. What the current development branch enforces

| Boundary | Implemented behavior |
| --- | --- |
| `POST /a2a` authentication | Host-provided `config.authenticate_request`; production/staging fail closed when no verifier is configured. |
| A2A Agent Card | Public `GET /.well-known/agent-card.json` declares supported HTTP **Bearer** requirements when configured. Absent/inconsistent security config fails closed in non-development/test environments. |
| Task authorization | Verified principal ID determines Task owner. `GetTask`, `ListTasks`, `CancelTask`, attempted Task continuation, filters and pagination are owner scoped in both MemoryStore and ActiveRecordStore. |
| Input handling | Bounded JSON request body, default 1 MiB; max configured limit 16 MiB; JSON Content-Type; compressed bodies rejected. |
| Error/log handling | Controlled 401/403/400/413/415/500 responses, `Cache-Control: no-store`, no raw Handler exception message in the Gem Task lifecycle log. |
| Pagination | Query/principal-bound opaque cursors. MemoryStore caps in-process snapshots at 128; ActiveRecordStore uses signed keyset cursors with an insert snapshot boundary. **This is not Task retention.** |

**Important limits:** The Gem does **not** verify Bearer tokens itself, decide permissions for business operations, issue OAuth tokens, authorize other services, provide a distributed rate limiter, or forcibly stop a Handler. Durable persistence is optional and must be explicitly selected/configured with ActiveRecordStore; MemoryStore remains the default.

## 2. Required host application configuration

A **conceptual initializer** (the verifier class must be implemented by the host, not copied as a working authenticator):

```ruby
A2A::Rails.configure do |config|
  config.agent = "YourAgent"
  config.public_base_url = "https://agents.example.com"
  config.max_request_bytes = 1_048_576
  # For multi-worker/restart-safe Task queries:
  config.task_store = :active_record

  config.security_schemes = {
    "bearer" => {
      "httpAuthSecurityScheme" => { "scheme" => "Bearer" }
    }
  }
  config.security_requirements = [
    { "schemes" => { "bearer" => { "list" => [] } } }
  ]
  config.authentication_challenge = 'Bearer realm="a2a"'

  config.authenticate_request = lambda do |request|
    # Implement this in YOUR application using a real, trusted verifier.
    # Do NOT check only whether the Authorization header is present.
    identity = YourApp::A2ATokenVerifier.verify(request.authorization)
    identity&.principal_id # stable non-secret, tenant-qualified String
  end
end
```

The host verifier **must** validate signature/issuer/audience/expiry/`nbf` (if applicable), key rotation, allowed client identity, permissions, and revocation policy. Fail closed on verification failure. Use a stable **tenant-qualified identity** (for example `"tenant-42:service-7"`) rather than the raw token or a client-supplied `contextId`. Distinct tenants must **never** return the same identity string.

An HTTP Bearer declaration is currently the only accepted Agent Card authentication profile. The `bearerFormat` field is optional—**do not claim JWT unless you actually use JWT**. If your host uses API-key headers, gateway-mTLS-only identity, OAuth2 scopes, or OIDC with a different advertised profile, this release does not yet support accurately publishing those schemes: do not misrepresent them as Bearer.

### Business actions and delegation

Being authorized to access *one's own Task* is **not** permission to purchase, send email, access private records, or invoke an Agent Skill. Each Handler must check the host application's permission model before causing effects. Enforce user/tenant/resource/action rules and side-effect idempotency within the application. ActingFor or other delegated-authorization tools can be integrated separately, but are neither required nor automatically enforced by this Gem.

The public Agent Card exposes Agent and Skill names, endpoint URLs and descriptions. Review these fields for sensitive business information before publishing the card.

## 3. Ingress, Rails, and resource protections — host responsibility

**All items below require actual deployment configuration; none are automatically supplied by a2a-rails.**

- **TLS / origin:** Serve only HTTPS with trusted certificates. Set an explicit HTTPS `public_base_url`. Restrict Rails allowed hosts and trusted proxies; only honor forwarded scheme/host/client-IP headers from your ingress. Do not expose the direct application port publicly.
- **Traffic shaping:** Apply a shared/distributed rate limiter **at the ingress, before Rails parses the body**, with per-client/principal and network-based abuse limits. Return `429` and a suitable `Retry-After` value. Apply concurrent request and connection caps.
- **Payload limits:** Set the reverse proxy body cap at or below the chosen Rails limit. Limit header size and time spent receiving a request. An application-side 1 MiB cap does not protect the upstream proxy from slow-body attacks.
- **Compute/cost:** Synchronous Handlers block Rails request workers. Enforce maximum execution time, DB/API timeouts, upstream spending limits, concurrency caps, and idempotent side effects. A Task cancellation does **not** interrupt running Handler code or roll back side effects.
- **Task storage:** MemoryStore remains process-local and must not be used for restart-safe or multi-worker Task queries. Step 21 adds optional [ActiveRecordStore](active-record-task-store.md) with owner-scoped SQL access, DB row locking, 30-day terminal retention by default, bounded pruning, owner admission guard and persisted collection limits. **The host must explicitly enable it, run the migration and operate pruning.** This removes the framework-level durability gap; it does not replace ingress/application security controls.
- **Observability:** Scrub Authorization headers, tokens, request/response bodies and SDK payloads from gateway, Rails, APM, error trackers, error pages and Handler logs. The Gem's own log filtering cannot sanitize all host middleware.
- **Credentials:** Use secret storage and rotate keys; never commit real tokens. Deny unauthenticated/invalid or revoked clients and minimize credentials' permitted scope.
- **Outbound dependencies:** Use allowlists, egress restrictions, HTTP timeouts and SSRF protections in every Handler that follows caller-supplied URLs, interacts with services or retrieves files.
- **CORS / browser:** Do not add permissive cross-origin access to A2A endpoints without a reviewed requirement; browser-based bearer handling deserves its own threat review.

## 4. Smoke checks before any external network access

**Never run the commands below with real credentials in shared terminal recordings or CI logs.** Perform these checks first in restricted staging using the exact **unreleased commit or future release candidate**, not published `v0.1.0`.

1. `GET /.well-known/agent-card.json` returns 200, advertises only the actual authentication scheme and an HTTPS `supportedInterfaces[].url`; it must **not** expose token values, client identities, internal hostnames or hidden Skills.
2. `POST /a2a` with no Authorization header returns **401** and `WWW-Authenticate: Bearer …`, without executing the Handler.
3. Expired, malformed, wrong-issuer, wrong-audience, revoked and insufficient-permission credentials are denied according to the host verifier's security policy (401 or 403).
4. A valid authorized request reaches its Handler; unauthorized business operations must still be rejected by the Handler/application policy.
5. Two distinct tenant-qualified principals cannot read/list/cancel each other's Tasks or reuse each other's page tokens, even with a known `taskId` or `contextId`.
6. Oversized body returns **413**, non-JSON Content-Type or compressed request **415**, malformed input **400**; failures do not echo secret values.
7. Exercise timeouts, parallel requests, restarts and gateway limits. If using MemoryStore, verify/document its expected loss/isolation. If using ActiveRecordStore, verify Tasks survive restart and are visible across workers against the actual deployment database.
8. Test TLS, trusted proxy headers, host allowlisting, 429/rate limits and secret scrubbing **at the deployed ingress**, not only through unit tests.
9. Inspect real production-shaped logs, traces and monitoring events for tokens, internal errors and sensitive Task content.
10. Run the Gem's 13-job CI matrix and packaged-Gem verification against the proposed release candidate.

## 5. Release and compatibility decision

**Do not publish a new Gem version from this documentation change alone.** The exact security feature set and deployment risks must be reviewed, versioned and verified as an artifact in a separate release process.

The published `v0.1.0` has no built-in A2A authentication or owner-scoped Task access. By contrast, the unreleased code changes the behavior of **production** endpoints:

- Production `POST /a2a` now denies unconfigured or invalid authentication.
- Production Agent Card discovery no longer succeeds without a valid advertised/verified security configuration.
- Task reads/list/cancel are restricted to verified owners.
- POST content type/body validation rejects requests accepted by earlier versions.
- The host must configure both its authentication callback **and matching Agent Card declarations**; setting only one is not enough.

These changes can break previously functional deployments and clients. Choose an appropriate **pre-1.0 SemVer-compatible version bump** after explicitly deciding whether to align the roadmap with this release. Do not silently call the current development state `v0.1.0`, and do not claim patch-version drop-in compatibility. Before tagging: update release notes, rerun packaged-artifact tests, exercise a clean host Rails app in **production environment** and verify the final published bytes against the candidate checksum.

## 6. Current security review outcome

| Item | Decision |
| --- | --- |
| Authentication / Task owner isolation / security metadata | Implemented in unreleased main; CI-covered. Application verifier and business authorization are still host responsibilities. |
| HTTP input checks and safer Gem error logging | Implemented in unreleased main; CI-covered. Gateway/middleware controls remain external. |
| Public multi-worker or restart-safe production | **Still not globally approved.** The Step 21 ActiveRecordStore removes the Gem-level persistence/worker-sharing blocker when explicitly configured and maintained, but deployment-specific auth, authorization, rate/concurrency limits, TLS/proxy policy, observability and execution budgets remain mandatory. |
| End-to-end production security | **Not approved** without a specific deployment review and the completed release checklist. |
| New RubyGems publication | **Not authorized by Step 16-6.** Prepare separately once user approves scope, version and artifact checks. |

See [A2A protocol security guidance](https://a2a-protocol.org/latest/specification/#7-authentication-and-authorization) and [enterprise deployment considerations](https://a2a-protocol.org/latest/topics/enterprise-ready/).
