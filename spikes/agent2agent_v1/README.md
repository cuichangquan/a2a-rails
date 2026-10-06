# agent2agent 2.0.0 / A2A v1.0 Spike

Step 15-4の使い捨て検証コード。a2a-rails Gemの実装ではない。

## 実行

Ruby **3.3以上**を使用する。SDKのgemspecは>=3.2だが、`protocol-http ~> 0.62`の依存により3.2では解決できない。

```sh
cd spikes/agent2agent_v1
bundle install
bundle exec ruby spike_test.rb
bundle exec rackup -s webrick -o 127.0.0.1 -p 9292
```

別terminalで:

```sh
curl http://localhost:9292/.well-known/agent-card.json
curl http://localhost:9292/a2a \
  -H 'Content-Type: application/json' \
  -H 'A2A-Version: 1.0' \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{"message":{"messageId":"message-1","role":"ROLE_USER","parts":[{"text":"Hello"}]}}}'
```

期待値: `result.task.status.state = TASK_STATE_COMPLETED`、ArtifactのText=`Echo: Hello`。

Rails境界の検証:

```sh
SPIKE_RAILS_VERSION='~> 8.0.0' bundle install
SPIKE_RAILS_VERSION='~> 8.0.0' bundle exec ruby rails_test.rb
```

Rails 8.1は`~> 8.1.0`に変更する。SDK単体とRailsありのbundleは異なる依存セットになるため、環境変更時はbundle installを行う。

## 検証範囲

- SDK本体は`gem "agent2agent", "2.0.0"`へ完全固定。
- 実SDKの`A2A.agent`、Schema、Error型、JSON-RPC serializerを利用。
- Echo SendMessage、GetTask、ListTasksのfilter/pagination/history/artifacts、CancelTask。
- Version header/query、未指定/空/非対応version。
- Streaming / Push / Extended Card無効時のerror。
- exact HTTP公開範囲、method、Content-Type。
- Railsのexact routeから同じSDKを利用。

## 限界

- 全仕様・全wire表現・公式TCKを通過した証明ではない。
- Messageの必須条件など、SDK schemaで不足するvalidationの一部を明示的に追加している。
- Echo専用の検証Handler。Gem本体の汎用Dispatcher / DSL / Generator / FAILED・REJECTED mappingは未実装。
- Memory Storeは単一process用。cursorはsnapshot方式で、expiryや容量制御は省略。
- 成功キャンセルはseedしたWORKING Taskと、同一processで同時実行したHandlerの状態保持で検証する。Handlerを中断せず、副作用も取り消さない。
- 認証・ユーザー別Taskの可視性はこのローカルSpikeでは検証しない。
- SDK本体をmountした場合の内部pathを直接公開しない。

結果と次の実装項目: [Step 15 findings](../../docs/design/sdk-compatibility-spike.md)。
