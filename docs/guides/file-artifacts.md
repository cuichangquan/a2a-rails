# File Artifact outputs (unreleased main, Step 17-3)

> **Not in published RubyGems v0.1.0.** File Artifact output is under development in [PR #23](https://github.com/cuichangquan/a2a-rails/pull/23). This is not a production deployment approval.

`a2a-rails` lets a Rails Handler return **one file Artifact** as an explicit `A2A::Rails::FileArtifact` object. The Gem converts it to an A2A v1.0 Part through its existing Task result pipeline; no SDK-specific objects are passed into the Handler.

## Raw bytes

```ruby
class Export::Report
  def self.call(message:, context:)
    data = File.binread("/trusted/app-generated/reports/report.pdf")

    A2A::Rails::FileArtifact.bytes(
      data: data,
      filename: "report.pdf",
      media_type: "application/pdf"
    )
  end
end
```

The bytes are **Base64-encoded once** to `artifacts[].parts[].raw`, accompanied by `filename` and `mediaType`. Binary strings are accepted; do **not** pre-encode the bytes as Base64. The limit is **1 MiB before encoding**. The resulting HTTP JSON body and process memory consumption will be larger because of Base64 overhead.

Do not use a file path supplied by an untrusted caller without first authorizing it and validating it against an allowlisted storage boundary.

## HTTPS file URL

```ruby
class Export::Report
  def self.call(message:, context:)
    A2A::Rails::FileArtifact.url(
      url: "https://files.example.com/reports/report.pdf",
      filename: "report.pdf",
      media_type: "application/pdf"
    )
  end
end
```

The Gem serializes `artifacts[].parts[].url` and **does not download, host, upload, probe or grant access to the file**. The host Rails application is responsible for generating a URL whose access controls fit the request's verified principal, and for lifecycle/expiry/retention. Prefer short-lived or appropriately authorized HTTPS URLs for private files.

Only an absolute `https://` URL with a host is accepted. `http://`, `file://`, relative URLs, embedded `user:password@` credentials, fragments, control characters, and URL strings longer than 2048 bytes are rejected. Query strings are accepted to support signed URLs; be aware that the query may contain sensitive credentials and must be scrubbed from logs and traces.

**Do not interpret a returned URL as having been checked for safety, availability, tenant ownership or download permissions.** A2A clients may independently fetch it.

## Common rules

- `filename` must be a nonempty basename (no `/`, `\\`, `.`, `..`, or ASCII control characters), at most 255 bytes.
- `media_type` is mandatory and must be of the MIME `type/subtype` form (e.g. `text/plain`, `application/pdf`, `image/png`). It is *not* inferred from the filename or file contents.
- `FileArtifact.bytes` accepts only Ruby String data up to 1 MiB; its internal copy/encoding prevents accidental mutation by the caller. The result object is immutable.
- Input `SendMessage` file Parts are **still unsupported**. Only the Handler's **output** mapping has been extended.
- Existing Handler return types remain: `String` → TextPart, `Hash/Array` → DataPart, `nil` → no Artifact. Invalid file result data or metadata raises `A2A::Rails::ArtifactMappingError`, which the Task lifecycle converts to a FAILED Task with a sanitized status.
- The generated Agent Card still defaults to text/plain. For a Skill that is deliberately returning PDFs/images, declare an appropriate `output_modes` for that Skill in its DSL to describe the real output.
- Existing output behavior still requires host-managed business authorization, response privacy, quota enforcement and a durable store before production scale-out.

## A2A wire examples

Raw file Part:

```json
{
  "artifactId": "sample-artifact-id",
  "parts": [
    {
      "raw": "SGVsbG8=",
      "filename": "hello.txt",
      "mediaType": "text/plain"
    }
  ]
}
```

URL file Part:

```json
{
  "artifactId": "sample-artifact-id",
  "parts": [
    {
      "url": "https://files.example.com/hello.txt",
      "filename": "hello.txt",
      "mediaType": "text/plain"
    }
  ]
}
```

## Test evidence

- `test/unit/file_artifact_test.rb` validates raw bytes, URL/filename/MIME constraints and size limits.
- `test/protocol/request_handler_integration_test.rb` exercises SendMessage, GetTask and ListTasks through the real Ruby A2A SDK.
- `test/support/tck_sut_server.rb` is the **localhost-only** host Agent for the pinned [official TCK](../testing/official-a2a-tck.md); it uses the public `FileArtifact` API, not fabricated protocol responses.
- The official TCK must still pass/fail/skip on its own merits. Fixing two specific `DM-ART-001` test scenarios does **not** imply complete A2A conformance.

See [production security review](production-security.md) for deployment limitations.
