# Step 29-5l — Nested Task / Artifact / history Message response validation

> **Unreleased Client only.** Implemented and tested locally in CI; this is not an overall security approval. Tracks [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90) and [Step 29-5k release-gate audit](step-29-5k-client-release-gates-audit.md). No changes to Cloud Run, GCP resource state, or public RubyGems 0.2.0. **v0.3.x NO-GO.**

## Threat and fix

Step 29-5j validated the **direct** `SendMessage.message.parts` oneof but did not apply the same structure checks to **nested Task reply** objects. A malicious or broken upstream agent could provide multiple oneof fields (`text/raw/url/data`), invalid payload types, missing Artifact IDs or malformed history/status Message arrays, which would previously reach callers as decoded objects.

The public Client now validates:

- A Task always has a nonempty `id`, a `status` object and nonempty `status.state` (existing gate).
- If present and non-null, `status.message` is a valid Message; `history` is an array of Messages; `artifacts` is an array of Artifacts. Empty `history`/`artifacts` arrays remain allowed.
- Messages require `messageId`, `role` and a nonempty Part list.
- Artifacts require `artifactId` and a nonempty Part list.
- Each Message/Artifact Part must be an object containing **exactly one of** `text`, `raw`, `url`, `data`. Text/raw/url values must be Strings; data values must be JSON objects (Hashes). Arbitrary metadata and data payloads are **not interpreted** or fetched.
- When a known protocol field is present in both its canonical camelCase and snake_case alias, reject as `InvalidResponseError(:ambiguous_protocol_key)` at the structured Task, status, Artifact, Message or Part boundary. The check is **not recursive into opaque data/metadata/extensions**.
- Decode-time `InvalidInputError` from inconsistent remote protocol keys is mapped into a **sanitized `InvalidResponseError`**, never misreported as caller input failure.
- Official `extensions` is a known protocol property and decodes to `:extensions`; unknown keys **inside** `metadata`/`data` and nested extension values retain their case, values and deep immutability.

These checks apply through **SendMessage(Task)**, **GetTask**, **ListTasks** (each returned Task) and **CancelTask**; valid direct Message handling is retained.

## Negative / positive evidence

`test/unit/client/public_api_test.rb` now covers:

1. Invalid nested Part oneof combinations, missing variants, invalid `data/raw/url/text` types, non-object Parts at each of **Artifact**, **status.message** and **history** locations.
2. Missing Artifact ID, missing or empty Parts, malformed Artifact and history arrays, invalid status/history Message shape.
3. Failure through all read/write Task-returning public operations.
4. Ambiguous protocol keys in Task Artifact and direct Message responses, with sanitized typed error and nil cause.
5. Valid rich File `raw`, `url` (opaque URL, **never fetched**), nested custom Data, extension IDs, status Message and history; all output remains deeply immutable.

The tests use a deterministic test-only fake resolver. No real external URLs, public agent services, credentials, changed CA trust roots or GCP resources are involved.

## Verification

```sh
bundle exec ruby -Itest test/unit/client/public_api_test.rb
bundle exec rake test
```

Before merge, require full GitHub Actions Ruby 3.3/3.4/4.0 + Rails 8.0/8.1 + packaged-Gem + installed-artifact/PG security checks and independent outbound interoperability jobs to pass.

## Remaining blockers

This is **structural validation**, not a comprehensive Protobuf schema validator. It does not fetch/verify remote Part URLs, validate base64 file contents or independently prove rich nested Task/File/Data in **both** official Python and Go servers (scheduled for Step 29-5n). The deeper log-sink and authorization boundary review (29-5m), queued separate worker testing (29-5o), independent v0.3 candidate security review, and distinct public/no-auth governance gate remain **OPEN**. Issue #90 remains **OPEN**, **v0.3.x NO-GO**.
