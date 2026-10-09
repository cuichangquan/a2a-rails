# Step 29-5q — Authenticated Go A2A SDK ListTasks and cross-owner isolation

> **Version:** official `a2a-go/v2@v2.6.0`; outbound `a2a-rails` **unreleased Client**. Local CI only, no Cloud Run/GCP changes or real secrets. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90), [Step 29-5n](step-29-5n-official-sdk-advanced-matrix.md) and the [v0.3.x NO-GO assessment](../release/v0.3.x-client-pre-release-security-review.md).

## Original cause

Step 29-5n proved Python ListTasks cursor pagination; the official Go server returned **JSON-RPC `-31401`** to the anonymous caller. Reading official **tag v2.6.0** source explains why: `a2asrv/taskstore.InMemory.List()` calls its configured `Authenticator(ctx)`, and rejects a **blank username** with `a2a.ErrUnauthenticated`. The default `a2asrv.NewHandler` sets `taskstore.NewInMemory` with `a2asrv.NewTaskStoreAuthenticator()`, which reads `CallContext.User.Name`. An unauthenticated caller has no username. This is **not evidence ListTasks is unsupported**.

## Test-only solution: SDK-native authenticated identity

The independent Go fixture now wires **`a2asrv.WithCallInterceptors`**, the SDK's documented request interception API. Its `Before` reads the HTTP `Authorization` field from `CallContext.ServiceParams()`, accepts only **two distinct hardcoded fake test bearer tokens**, and calls the SDK's `a2asrv.NewAuthenticatedUser(name, nil)`. Missing/invalid tokens produce the SDK's own `a2a.ErrUnauthenticated`, mapped by its unmodified JSON-RPC handler to `-31401`. The SDK's **default owner-aware InMemory Task Store remains unchanged**. It scopes stored Tasks to the user identity and masks cross-owner Task reads as not found. The test Agent Card declares its actual Bearer auth scheme with the SDK's `securitySchemes`/`securityRequirements` model, and remains available without a Card token. The test-only token callback is bound to the **exact native RPC origin**, never shared with Agent Card discovery.

No bypass of the store, fabricated ListTasks response, monkey-patched JSON-RPC handler, forged user parameter or `Task Store.Authenticator = constant user` is used. The fixture listens only on `127.0.0.1` with an ephemeral local TLS certificate; the Rails Client's normal public constructor still rejects this synthetic test host. The old internal **test-only** loopback pin/CA adapter is injected solely into the probe.

## Required observations

| Case | Acceptance evidence |
| --- | --- |
| Go anonymous ListTasks | SDK returns a sanitized `RemoteError(code=-31401)`, nil cause |
| Go invalid bearer ListTasks | Same SDK-native `-31401`; cannot list any Tasks |
| Go authenticated tenant A | `ListTasks(page_size: 1)` yields a Task + nonempty SDK cursor; next page with `page_token` yields a **different** tenant-A Task |
| Go authenticated tenant B | Authenticated SendMessage creates its **own** Task; ListTasks returns only this one Task, empty next cursor |
| Cross-owner GetTask | A cannot read B Task and B cannot read A Task; SDK returns typed sanitized numeric remote errors, never a foreign Task |
| Existing SDK coverage | Official SDK direct/rich Message, Artifact, GetTask, InputRequired, CancelTask, missing Task and Python original matrix remain PASS |
| Authentication metadata | SDK-produced Card declares Bearer requirement; Card GET remains unauthenticated; RPC bearer is provided per exact origin |

**Verified:** [Step 29-5b official native HTTPS CI run #37997186725](https://github.com/cuichangquan/a2a-rails/actions/runs/37997186725) **2/2 PASS** (Python and Go). Go output includes `STEP 29-5q GO SDK AUTHENTICATED LISTTASKS: PASS (two pages, cross-owner denial)` and `STEP 29-5n SDK CAPABILITIES GO: {cancel_task: "PASS", list_tasks: "PASS", get_missing_task: "PASS"}`. Both anonymous and invalid bearer negative checks returned **`-31401`**; both directions of foreign GetTask were refused; tenant A's two cursor pages and tenant B's isolated list passed. Supporting [SDK/Gem matrix #37997186739](https://github.com/cuichangquan/a2a-rails/actions/runs/37997186739) and [Step 29-1 outgoing client spike #37997186765](https://github.com/cuichangquan/a2a-rails/actions/runs/37997186765) also PASS. These are PR-head source tests, **not** a versioned 0.3.x candidate artifact or independent security review.

## Reproduction

`/.github/workflows/a2a-outbound-official-servers.yml` runs Python 3.12 and Go 1.26.0 native HTTPS SDK servers. The Go v2.6.0 TaskStore and handler are **official code**, not local copies. Run `bundle exec ruby -Ilib spikes/a2a_client_v03/official_sdk_native_https_probe.rb` against the test-only server with the certificate and `STEP29_5B_AGENT=go` environment as in the workflow. No real external IP, HTTPS domain, production OAuth, token issuer, PostgreSQL, public Cloud Run or GCP expense is involved.

## Residual release gates

The test has **fixed fake tokens** and a single-process ephemeral SDK Task Store: it does not validate real production identity provider signature/revocation, cross-host storage, production multi-tenant authorization, pagination under concurrent deletion or exhaustive cursor tampering. **Do not treat this as generic authorization certification**. Separately pending: exact **versioned v0.3.x candidate** Gem SHA256 and installed Client+PG tests, independent security review and owner release approval, plus written decision about separately unapproved public/no-auth Cloud Run acceptance criterion. **Issue #90 OPEN, v0.3.x NO-GO; published stable RubyGems remains 0.2.0.**
