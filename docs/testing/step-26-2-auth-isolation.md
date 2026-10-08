# Step 26-2 — Installed-Gem authentication and tenant-isolation evidence

Date: **2026-10-08**  
Track: **A2 — Gem release gate**, [Step 26 issue #62](https://github.com/cuichangquan/a2a-rails/issues/62).  
Implementation: [PR #67](https://github.com/cuichangquan/a2a-rails/pull/67) and [test fixture](../../test/support/installed_auth_isolation_smoke.rb).  
Evidence: [GitHub Actions candidate verification #37716562279](https://github.com/cuichangquan/a2a-rails/actions/runs/37716562279): **Rails 8.0 and 8.1 installed-artifact security smoke PASS**, including the Step 26-2 fixture.

## Trust boundary under test

The host Rails application owns `config.authenticate_request`, the token verification implementation, and its issuer/audience/revocation policy. `a2a-rails` authenticates **before** protocol dispatch, accepts only a stable non-secret principal ID, and scopes Task operations to that verified ID. It does **not** implement an OAuth/OIDC issuer or claim that presence of a Bearer header is verification.

For a deterministic, reproducible integration test only, the fixture implements local JWT-HS256 minting/verification using Ruby `openssl`, without any Gem runtime dependencies or third-party identity service. The fixture's signing key, issuer, tenant and token strings are **test data, not suitable for real authentication**.

## Checked through Rack HTTP into an installed Gem

| Category | Evidence |
| --- | --- |
| Candidate provenance | Source-built exact Gem installed into an isolated Rails 8.0 and 8.1 bundle; version and non-source path asserted |
| Fail-closed configuration | Production Agent Card is HTTP 503 before valid verifier/security metadata; POST is HTTP 401 if authenticator missing, HTTP 500 with sanitized response when metadata mismatches |
| Negative credentials | Missing/garbage token; modified claims with old signature; wrong signing key; expired; future `nbf` and `iat`; wrong `iss`/`aud`; revoked; missing tenant/subject; unknown `kid`; `alg=none` |
| Host policy | Explicit forbidden signal yields HTTP 403; unexpected verifier exception yields generic HTTP 500 |
| Handler/Task protection | No invalid credential invokes Handler or creates a Task; legitimate verified tenant-qualified principal reaches Handler |
| Agent Card | Advertises only the configured Bearer JWT-style HTTP scheme and matching security requirements; correct HTTPS public URL; `Cache-Control: no-store` |
| Task ownership | Different tenant with **same subject** cannot Get/Cancel/continue foreign Task or enumerate its Task IDs or `totalSize` |
| Pagination | Legitimate owner fetches both pages; cross-tenant token reuse and changed context/page-size fail with JSON-RPC invalid-query error |
| Revocation | Token authorized once becomes unauthorized on subsequent Task access immediately after host fixture revokes its `jti` |
| Sanitization | Credentials, private signing fixture string and intentional verifier-exception message are absent from returned Agent Card and captured auth logger; HTTP errors remain generic |
| Existing regressions | Original production security smoke remains in same CI matrix; separate A1 PostgreSQL storage/clean-host and other compatibility jobs remain independent |

The tests exercise **Rails production environment at its Rack HTTP boundary** with the Gem as an installed package. The Step 26-2 fixture uses the **default in-process MemoryStore** deliberately to isolate auth behavior. PostgreSQL persistence and clean generated-host startup are independently verified by [Step 26-1](published-gem-postgres.md) and the clean-host CI matrix; this is **not** a claim that this auth fixture itself tests PostgreSQL, an external IdP, or a live network proxy.

## Limitations / production remains NO-GO

- HMAC JWT fixture is test-only; not an audited OIDC/JWT verification library, production key store, rotation or issuer service.
- Actual TLS ingress/trusted proxies, distributed rate/concurrency/cost limits, revocation consistency across hosts, application-specific Handler business authorization, audits, and data leakage in **host/framework log pipelines** require **per-deployment** integration and review.
- A2A Gem does not guarantee that a given Handler verifies user permissions on real business resources. An authenticated Task principal is **not** an authorization policy.
- This run uses a newly built **source candidate** reporting version `0.2.0.rc2`. The old RubyGems-published `0.2.0.rc2` artifact remains immutable and does not contain changes merged on main since publication.
- Passing A2 does **not** satisfy A3 (durable async failure windows) or A4 (new exact stable `0.2.0` artifact/authorization). No publishing has occurred.
- [Production Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11) remains **OPEN**.

## Re-running

The established [Release candidate artifact verification workflow](../../.github/workflows/release-candidate-artifact.yml) builds one exact candidate Gem, checks its SHA256, installs the same artifact with Rails 8.0 and 8.1, and runs:

```bash
RAILS_ENV=production RACK_ENV=production \
A2A_RAILS_EXPECTED_VERSION=0.2.0.rc2 \
A2A_RAILS_SOURCE_ROOT=/path/to/source-checkout \
BUNDLE_GEMFILE=/path/to/clean-host/Gemfile \
bundle exec ruby test/support/installed_auth_isolation_smoke.rb
```

Use an isolated test environment; do not reuse its credentials or verification code as production authentication.
