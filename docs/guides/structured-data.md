# Call Rails business logic with structured Data

Server Data input is available in [published a2a-rails 0.4.0](https://rubygems.org/gems/a2a-rails/versions/0.4.0).
In an existing Rails app, run `bundle add a2a-rails --version '= 0.4.0'`.
Version 0.3.0 supports the outbound Client and Server Data output, but not
Server Data input.

## Server: opt in on the selected Skill

Keep the normal generated Rails/Engine setup from the [Quick Start](../../README.md#server-quick-start-local-development).
The only change at the A2A boundary is a Skill declaration and a Handler that
reads a Data Part. Put business validation in a Service callable from other
Rails code too. For example:

```ruby
class ReportTotals
  def self.call(month:)
    return { "sales_count" => 3, "total_amount" => 35_000, "currency" => "JPY" } if month == 10

    raise ArgumentError, "Only October is available in this example"
  end
end

class ReportHandler
  def self.call(message:, context:)
    part = message.fetch(:parts).first
    unless message.fetch(:parts).one? && part.key?(:data) && part[:data]["month"] == 10
      raise A2A::Rails::RejectedTask, "Send one JSON object with month set to 10"
    end

    ReportTotals.call(month: part.fetch(:data).fetch("month"))
  end
end

class ReportsAgent < A2A::Rails::Agent
  name "Reports"
  description "Read-only October sales totals"
  version "1"
  skill :report, description: "Summarize sales", tags: ["reports"],
    input_modes: ["application/json"], output_modes: ["application/json"], handler: ReportHandler
end
```

Set `config.agent = "ReportsAgent"` in the existing initializer. If the Agent
has multiple Skills, use its existing `router` to select one. The selected
Skill, not a different Skill advertised in the Card, must declare
`application/json`. The Card lists this in the Skill's `inputModes`; the
top-level default for Skills without a declaration stays `text/plain`. A
declaration enables Data input; it does not make existing text callers invalid.
The Router can inspect a well-formed Data Part to route it; the Handler cannot
receive it unless the chosen Skill opted in.

## Input and output contract

| Boundary | Behavior |
| --- | --- |
| Server input | One or more Data Parts, each with a JSON **object** in `data`. Inside the object, strings, numbers, booleans, null, objects and arrays are preserved. Top-level arrays/scalars/null are not admitted. |
| MIME type | Omitted `mediaType` becomes `application/json`. If explicit, use exactly `application/json`; parameters, empty/null values and other MIME types are not accepted. The SDK's `media_type` alias is accepted alone; specifying both is invalid. |
| Part kinds | Exactly one of `text`, `data`, `raw` or `url` per Part, based on field presence. Mixed text and Data Parts in one Message are not supported. File input and URL fetching remain unsupported. |
| Handler | `call(message:, context:)` is unchanged. A normalized Part is `{ data: { "month" => 10 }, media_type: "application/json" }`. Only the protocol envelope uses symbol keys. Data keys such as `messageId` and `message_id` are independent strings. |
| Stored history | MemoryStore and ActiveRecordStore retain the Data and canonical MIME type. ActiveJob reads the original Message from the Store, not from a duplicate job payload. No migration is required. AR now keeps string keys **inside Data Parts**, including existing rows when read; metadata is unchanged. |
| Server output | A Handler may return a Hash **or an Array** of JSON values, including nested `nil` (wire `null`), via a Data Artifact or a direct Message. Text and FileArtifact output are unchanged. |
| Failure | Unsupported media/mixed Parts or a Skill without Data opt-in result in a protocol error before Task creation. Business validation belongs in the Handler/Service and can produce a rejected Task in Task mode. Direct Message mode still does not create Tasks. |

Request limits, Task ownership, authorization, outbound HTTPS policy and
transport are unchanged. Authorize the business operation in the host
application; an Agent Card is a capability description, not a permission.

## Client: send filters, read the result

Assuming a Client configured with the Server's real HTTPS Agent Card and exact
allowed origin (see [Outbound Client](outbound-a2a-client.md)):

```ruby
result = client.send_message(message: {
  message_id: SecureRandom.uuid,
  role: "ROLE_USER",
  parts: [{ data: { "month" => 10 }, media_type: "application/json" }]
})
task = result.task
if task && task.dig(:status, :state) == "TASK_STATE_COMPLETED"
  totals = task.fetch(:artifacts).flat_map { |artifact| artifact.fetch(:parts) }
    .find { |part| part.key?(:data) }
  puts totals.fetch(:data)
else
  puts task&.dig(:status, :state) || "Expected a Task response"
end
```

This example assumes a synchronous Task and a known report result. The Client
does not retry or poll automatically. Calling the Service directly skips A2A
routing, admission, Task storage and transport; use it for local Rails callers.
To see the complete three-field fictional sales example and the real HTTPS
test, use the
[Server demo](https://github.com/cuichangquan/a2a-rails-demo) and
[Client demo](https://github.com/cuichangquan/a2a-rails-client-demo)
structured-report guides. Check each README for its exact RubyGems pin.

SSE, Task continuation, push delivery, and file input are outside this release. The new Data input support is not a claim of full A2A conformance.
