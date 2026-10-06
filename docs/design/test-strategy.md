# a2a-rails v0.1 Test Strategy

## Goal

v0.1のテストは、A2A Protocolそのものや下位Ruby SDK内部を再テストするのではなく、a2a-railsが責任を持つRails Integration境界を保証する。

```text
Rails-facing API
      ↓
a2a-rails
      ↓
Protocol Adapter
      ↓
Ruby A2A SDK
```

## Test Framework

Gem本体のテストには **Minitest** を使用する。

- `ActiveSupport::TestCase` をUnit Testの基本とする
- `ActionDispatch::IntegrationTest` をRails request / integration testに使用する
- Gem本体はRSpecへ依存しない
- 利用側Rails applicationのテストフレームワークには依存しない

## Test Layers

v0.1では4層に分ける。

```text
4. Protocol E2E / Smoke Tests
3. Rails Integration Tests
2. Adapter Contract Tests
1. Core Unit Tests
```

### 1. Core Unit Tests

Rails HTTP stackや実SDKを通さず、Gem内部ロジックを直接テストする。

対象:

- Agent / Skill DSL
- Configuration
- Dispatcher
- Task Lifecycle
- Artifact Mapping
- Task Store
- Error handling

Unit TestではRails routing、HTTP endpoint、JSON-RPC全体、本物のRuby A2A SDKは扱わない。

### Agent / Skill DSL

保証する内容:

- `name`, `description`, `version`
- Skill登録
- Skill ID / name生成
- 必須項目Validation
- Skill ID重複拒否
- Handlerが `.call` に応答すること

### Configuration

保証する内容:

- `config.agent`
- `config.public_base_url`
- `config.logger`
- 必須設定不足や不正設定のError

### Dispatcher / Handler Boundary

Dispatcherの責務は薄く保つ。

```text
1. Skillを解決
2. Handlerを取得
3. handler.call(message:, context:) を呼ぶ
4. resultを返す
```

保証する内容:

- 正しいSkill / Handlerを選択する
- `message` / `context` を正しく渡す
- Handlerの戻り値をそのまま次の層へ返す
- Unknown Skillは `A2A::Rails::UnknownSkillError`
- Invalid Handlerは `A2A::Rails::InvalidHandlerError`

DispatcherではTask state変更、Artifact変換、Task保存、Protocol response生成を行わない。

### Task Lifecycle

正式なv0.1実行経路:

```text
SUBMITTED
    ↓
WORKING
    ├──→ COMPLETED
    ├──→ REJECTED
    └──→ FAILED
```

保証する内容:

- Task初期状態は `SUBMITTED`
- Handler実行前に `WORKING`
- 通常returnは `COMPLETED`
- `A2A::Rails::RejectedTask` は `REJECTED`
- unexpected exceptionは `FAILED`
- terminal stateから再遷移しない
- unexpected exception詳細はloggerへ記録する
- 外部Taskにはgeneric failure messageのみを公開する

`CANCELED` はstateとして認識するがv0.1の通常フローでは到達しない。
`INPUT_REQUIRED` / `AUTH_REQUIRED` はv0.1 Scope外。

### Artifact Mapping

v0.1で正式にサポートするHandler return:

```text
String       → Text Part
Hash / Array → Data Part
nil          → Artifactなし
その他       → explicit mapping error
```

ActiveRecord objectなどの任意Objectを暗黙serializeしない。

未対応型にはGem側の明示的なErrorを使用する。実装時にError class名を最終確定する。

### Task Store / GetTask

Memory Task Storeで保証する内容:

- Task保存
- Task IDによる取得
- 保存後の更新
- 複数Taskの分離
- `context_id` の保持
- unknown taskのNot Found扱い

GetTaskでは以下を取得できることを保証する。

- current status
- artifacts
- message history

Memory Task Storeでは以下を保証しない。

- Rails process restart後の保持
- multi-process共有
- DB transaction

## 2. Adapter Contract Tests

Protocol AdapterとRuby A2A SDKの境界互換性をテストする。

Unit TestではSDKをmockし、Contract Testでは実SDKを使用する。

主な対象:

- SDK Request → a2a-rails内部表現
- a2a-rails Task → SDK Response
- Message
- Task / TaskState
- Artifact / Part
- Agent Card
- `message/send`
- `tasks/get`
- Protocol error mapping

SDK内部のserializationやvalidationロジックそのものは再テストしない。

SDKを将来交換した場合も、同じContract要件を新Adapterへ適用する。

## 3. Rails Integration Tests

`test/dummy` のRails applicationを使用する。

### Agent Card endpoint

```text
GET /.well-known/agent-card.json
```

保証する内容:

- HTTP 200
- JSON response
- Agent `name`, `description`, `version`
- Skill `id`, `name`, `description`, `tags`
- Handler情報を外部公開しない
- `supportedInterfaces` が `/a2a` を指す
- unsupported capabilitiesが有効になっていない
- `config.public_base_url` を優先する
- 未指定時は `request.base_url` を利用する
- Invalid Agent定義から部分的なAgent Cardを公開しない

### A2A endpoint

```text
POST /a2a
```

Rails requestから以下を実際に通す。

```text
POST /a2a
   ↓
Protocol Adapter
   ↓
Dispatcher
   ↓
Handler
   ↓
Task Lifecycle
   ↓
Task Store
   ↓
Response
```

主要ケース:

- successful execution → `COMPLETED`
- business rejection → `REJECTED`
- unexpected exception → `FAILED`
- unknown skill
- invalid request
- `tasks/get`

Gem内部の主要コンポーネントはIntegration/E2Eでは原則mockしない。
Rails application側の外部APIなどGem責務外の依存はstub可能。

## 4. Protocol E2E / Smoke Tests

実Rails dummy applicationと実Ruby A2A SDKを通す。

v0.1 Critical Pathは最低限以下の5本とする。

```text
1. Agent Card取得
2. message/send → COMPLETED
3. message/send → REJECTED
4. message/send → FAILED
5. tasks/get → 保存済みTask取得
```

この5本はv0.1のリリース可能性を判断するCritical E2Eとする。

## Test Layout

概念上の構成:

```text
test/
├── a2a/
│   └── rails/
│       ├── agent_test.rb
│       ├── skill_test.rb
│       ├── configuration_test.rb
│       ├── dispatcher_test.rb
│       ├── task_lifecycle_test.rb
│       ├── artifact_mapper_test.rb
│       └── task_store_test.rb
├── adapters/
│   └── agent2agent_adapter_test.rb
├── requests/
│   ├── agent_card_test.rb
│   └── a2a_endpoint_test.rb
├── integration/
│   └── a2a_flow_test.rb
└── dummy/
    └── Rails application
```

実際のdirectory namesはStep 13: Gem Structureで最終確定する。

## CI Policy

Pull Requestおよび`main` pushでは以下をすべて実行する。

```text
Unit Tests
Adapter Contract Tests
Rails Integration Tests
Critical E2E Tests
```

どれか1つでも失敗したらCIを失敗させる。

Release時はSupported Ruby / Rails matrixの全組み合わせでGreenを必須とする。

具体的なSupported Ruby / Rails versionsはStep 13のgemspec設計で確定する。

v0.1ではNightly CIを導入しない。

## Final Decision

v0.1 Test Strategy:

> Minitestを使用し、Core Unit / Adapter Contract / Rails Integration / Protocol E2Eの4層でテストする。ProtocolそのものやSDK内部を再テストせず、a2a-railsが責任を持つRails IntegrationとSDK境界を重点的に保証する。

Step 12: Test Strategy is complete.

Next: **Step 13 — Gem Structure**.
