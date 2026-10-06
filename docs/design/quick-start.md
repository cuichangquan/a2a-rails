# a2a-rails v0.1 Quick Start Design

> **Status: Step 14 design complete. Step 15-12 runtime-verifies the generator-backed Echo Quick Start both from source and from the built `a2a-rails-0.1.0` gem installed into a clean Rails application.**

This document fixes the first-time developer experience for an existing Rails application. The example uses Echo to keep the Gem independent of any business domain.

## 1. Golden Path

1. Add the Gem.
2. Generate the initializer.
3. Generate one Agent.
4. Create one application-owned Handler and register one Skill.
5. Register the Agent by class-name String and start Rails.
6. Retrieve the Agent Card.
7. Send a message and receive a completed Task with an Echo Artifact.

No database, ActiveJob, authentication, LLM, streaming, or explicit Engine mount is required for this Quick Start.

## 2. Generator Contract

Step 15-11 implements the exact generator namespaces:

```bash
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent echo
```

`install` creates only `config/initializers/a2a_rails.rb`:

```ruby
A2A::Rails.configure do |config|
  config.agent = "YourAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

`agent echo` creates only `app/agents/echo_agent.rb`:

```ruby
class EchoAgent < A2A::Rails::Agent
  name "Echo Agent"
  description "TODO"
  version "1.0"

  # Add at least one skill.
end
```

The generated Agent does not reference a nonexistent Handler. It is a scaffold, not a valid public Agent until a Skill is added.

Generators do not create:

- Handlers;
- controllers;
- routes;
- migrations;
- Task Stores;
- jobs;
- authentication configuration;
- automatic Agent registration.

Handler placement remains an application choice. `app/services` is used below only as an example.

### Runtime verification

Step 15-11 invokes the generators by their Rails namespace, verifies the exact generated file contents, and then uses those files as the starting point for the Echo application smoke test.

Step 15-12 repeats that contract from the **built and installed gem** in a clean Rails 8.1 application. The verification explicitly proves that Bundler resolves `a2a-rails-0.1.0` from the installed RubyGems path rather than from the repository checkout before invoking the generator CLI.

## 3. README Quick Start

> The flow below is runtime-verified from both the repository source tree and the packaged gem installed in a clean Rails application. `bundle add` still describes the intended released-gem experience; it does not mean the Gem has already been published.

### Add and install

```bash
bundle add a2a-rails
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent echo
mkdir -p app/services/echo
```

### Create the Handler

Create `app/services/echo/reply.rb`:

```ruby
class Echo::Reply
  def self.call(message:, context:)
    text = message[:parts]
      .filter_map { |part| part[:text] }
      .join("\n")

    "Echo: #{text}"
  end
end
```

### Define the Skill

Replace `app/agents/echo_agent.rb` with:

```ruby
class EchoAgent < A2A::Rails::Agent
  name "Echo Agent"
  description "Echo messages"
  version "1.0"

  skill :reply,
    description: "Echo a message",
    tags: %w[echo],
    handler: Echo::Reply
end
```

A single Skill is selected automatically. No Router is needed for this example.

### Register the Agent

Replace `config/initializers/a2a_rails.rb` with:

```ruby
A2A::Rails.configure do |config|
  config.agent = "EchoAgent"
  config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
end
```

For localhost, leave `A2A_PUBLIC_BASE_URL` unset or set it to `http://localhost:3000`. An explicit base URL takes precedence over the request base URL and must not contain `/a2a`.

Configuration keeps the class name as a String. The Agent is resolved and validated only when an A2A endpoint needs it, so initializer evaluation does not eagerly resolve the application constant.

```bash
bin/rails server
```

No change to `config/routes.rb` is required. The Engine mounts its A2A routes automatically at `/`.

### Check the Agent Card

```bash
curl -sS http://localhost:3000/.well-known/agent-card.json \
  -H "A2A-Version: 1.0"
```

Confirm:

- HTTP 200;
- Agent name `Echo Agent`;
- Skill ID `reply`;
- JSON-RPC protocol version `1.0`;
- endpoint URL `http://localhost:3000/a2a` when no explicit public base URL is configured.

The Agent Card Builder uses `config.public_base_url` when present, otherwise the current request base URL, then appends `/a2a`. Generated Cards pass the real `agent2agent 2.0.0` Agent Card schema and never expose Handler internals.

### Send the First Message

```bash
curl -sS -X POST http://localhost:3000/a2a \
  -H "Content-Type: application/json" \
  -H "A2A-Version: 1.0" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "SendMessage",
    "params": {
      "message": {
        "messageId": "msg-1",
        "role": "ROLE_USER",
        "parts": [{"text": "Hello"}]
      }
    }
  }'
```

The request supplies a Message ID and omits Task ID and Context ID. The server generates Task ID and Context ID. No custom Skill selector is sent.

Default v0.1 execution is synchronous. This Echo Handler completes during the same request.

Illustrative success response:

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "result": {
    "task": {
      "id": "task-generated-id",
      "contextId": "context-generated-id",
      "status": {"state": "TASK_STATE_COMPLETED"},
      "artifacts": [
        {
          "artifactId": "artifact-generated-id",
          "parts": [{"text": "Echo: Hello"}]
        }
      ]
    }
  }
}
```

Success means:

- `result.task.status.state` is `TASK_STATE_COMPLETED`;
- Task ID and Context ID are present;
- a Text Part in the Task Artifacts contains `Echo: Hello`.

Exact IDs, timestamps, optional fields, and Artifact metadata are not fixed fixtures.

Step 15-12 verifies this sequence from a clean Rails application using the built `.gem`, including actual `bin/rails generate` commands and the installed Gem runtime.

## 4. Skill Routing

A2A v1.0 `SendMessageRequest` and `Message` do not define a standard `skill_id`. Agent Card Skills advertise capabilities; they are not protocol method selectors.

- One Skill: dispatch automatically to its Handler.
- Multiple Skills: require an application-owned Router.
- Never silently select the first Skill.
- Do not introduce a required custom Skill selector into the Quick Start request.
- a2a-rails does not provide LLM routing or application business-routing rules.

Example:

```ruby
class ShoppingAgent < A2A::Rails::Agent
  router Shopping::AgentRouter

  skill :search_products,
    description: "Search products",
    tags: %w[shopping search],
    handler: Shopping::SearchProducts

  skill :purchase_product,
    description: "Purchase products",
    tags: %w[shopping purchase],
    handler: Shopping::PurchaseProduct
end
```

```ruby
class Shopping::AgentRouter
  def self.call(message:, context:, skills:)
    # skills is a frozen Array<Symbol> of declared Skill IDs.
    :search_products
  end
end
```

The Router may return a matching Symbol or String. Unknown selections raise `A2A::Rails::UnknownSkillError`. The Dispatcher never silently falls back to another Skill.

`skill_id` is added only after selection to a new Handler context; the incoming context is not mutated.

## 5. Handler Boundary

Public Handler interface:

```ruby
def self.call(message:, context:)
end
```

The Protocol layer supplies ordinary Ruby Hashes, not SDK-specific schema objects.

Quick Start Message:

```ruby
{
  message_id: "msg-1",
  role: :user,
  parts: [{ text: "Hello", media_type: "text/plain" }],
  metadata: {}
}
```

Handler context:

```ruby
{
  task_id: "task-generated-id",
  context_id: "context-generated-id",
  skill_id: :reply
}
```

`ROLE_USER` maps to `:user`. Missing Message metadata normalizes to `{}`. For a text Part, omitted media type normalizes to `text/plain`.

`skill_id` is internal dispatch information, not a standard A2A request field.

v0.1 does not introduce public `A2A::Rails::Message`, `Context`, or `TextPart` value classes. Task and Artifact conversion remains internal.

## 6. First-Time Error Experience

Adding the Gem or running a generator must not fail Rails boot merely because the generated Agent is incomplete or unregistered. Resolve and validate the configured Agent when an A2A endpoint is used.

The generated `EchoAgent` therefore intentionally has no Skill until the developer adds one.

| Cause | Developer-facing error/log | Client behavior |
| --- | --- | --- |
| `config.agent` is nil or cannot be resolved | `ConfigurationError` | No partial Agent Card or dispatch |
| Agent has zero Skills | `ConfigurationError`: Agent must define a Skill | No partial Agent Card or dispatch |
| Handler lacks `.call` | `InvalidHandlerError` | No Handler dispatch |
| Multiple Skills without Router | `ConfigurationError` | No arbitrary fallback |
| Handler raises unexpectedly | detailed Rails log | generic `TASK_STATE_FAILED` response |

Static Agent / Skill validation occurs before Task creation. Once execution starts, `RejectedTask` maps to REJECTED and unexpected Handler exceptions map to a generic FAILED Task.

Task-not-found, non-cancelable Task, and invalid Task query errors are translated to SDK errors only inside the Protocol Adapter. Ruby class names, stack traces, and raw unexpected exception messages are not returned to clients.

The upstream SDK's `A2A::Server::Triage` can log the full Rack environment at INFO. The Rails-facing adapter suppresses that specific subject for each call/fiber and restores the prior Console logger state afterward.

## 7. Runtime Verification

Implemented and verified through Step 15-12:

- Agent metadata / Skill DSL;
- Skill and callable Handler validation;
- optional Skill Agent Card metadata (`examples`, `input_modes`, `output_modes`);
- single-Skill automatic dispatch;
- multi-Skill Router dispatch with frozen Symbol Skill IDs;
- Handler `skill_id` context injection;
- Task creation and terminal transitions;
- String / Hash / Array / nil Artifact mapping;
- explicit `ArtifactMappingError` for unsupported result types;
- FAILED / REJECTED result mapping;
- atomic cancellation and terminal-state overwrite protection;
- thread-safe in-memory Task storage;
- `ListTasks` filtering and pagination;
- `SendMessage`, `GetTask`, `ListTasks`, and `CancelTask` through the real SDK;
- cancellation-race verification;
- lazy Configuration and Agent resolution;
- Agent Card generation validated by the real SDK schema;
- automatically mounted Rails Engine;
- real host-Rails Agent Card and `/a2a` HTTP paths;
- shared process-local Runtime / Task Store across requests;
- SDK Triage logging suppression at the Rails boundary;
- `a2a:rails:install` generator;
- `a2a:rails:agent NAME` generator;
- exact generated initializer / Agent scaffold contract;
- generator namespace invocation;
- generated Echo setup → Rails boot → Agent Card → `SendMessage → TASK_STATE_COMPLETED` → `Echo: Hello`;
- built `.gem` inspection for required runtime / generator files;
- installed packaged-gem path proven independent of the source checkout;
- clean Rails 8.1 app + actual generator CLI + Echo HTTP flow.

Current verification result:

```text
Ruby: 3.3 / 3.4 / 4.0
Rails: 8.0 / 8.1
CI: 13 / 13 green
Gem suite: 70 tests / 240 assertions / 0 failures / 0 errors / 0 skips
Packaged gem SHA256: 09c55122c5d5e6cb5f9b735664d70b000f67d23dcaad9f4a8ff960dbe02dd410
```

## 8. Packaged Gem Verification

Step 15-12 builds `a2a-rails-0.1.0` and verifies that the artifact contains the required Engine, routes, generator classes, and generator templates. The smoke installs that artifact with RubyGems and creates a clean Rails 8.1 application outside the repository checkout.

Before running any generator, the test checks the loaded Gem path and rejects the run if `a2a-rails` resolves back to the source repository. It then executes:

```bash
bin/rails generate a2a:rails:install
bin/rails generate a2a:rails:agent echo
```

The generated files are compared with the fixed scaffold contract. The documented Echo edits are then applied and the clean application verifies Agent Card retrieval and `SendMessage → TASK_STATE_COMPLETED → Echo: Hello`.

Two verification-harness issues were intentionally caught while establishing this boundary:

1. launching the smoke under the repository's `bundle exec` leaked `BUNDLE_GEMFILE` into child processes and correctly triggered the source-path guard;
2. a minimal Rails fixture needed `--skip-asset-pipeline` when using the deliberately narrow clean-app Gemfile.

Neither was a Gem runtime defect; both improved the isolation of the packaged-artifact test.

The implementation/packaging path is now verified. Publishing is a separate release action and has **not** been performed.

**Next: Step 15-13 — Prepare the v0.1.0 release candidate and release checklist without publishing yet.**

## Official References

- [A2A specification: JSON-RPC binding and versioning](https://github.com/a2aproject/A2A/blob/main/docs/specification.md)
- [A2A schema: Message, Part, Task, Artifact, SendMessageRequest/Response](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto)
