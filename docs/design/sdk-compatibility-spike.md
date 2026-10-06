# Step 15: Ruby SDK / A2A v1.0 Compatibility Spike

## 状況

`agent2agent 2.0.0`の実Gemを用いた独立Spikeを実装した。
**Step 15-4の実行検証は完了。** Gem本体の実装・完全互換性認証は未完了。

## 実行結果（2026-10-06）

[成功CI](https://github.com/cuichangquan/a2a-rails/actions/runs/37431440117) — code commit `15ea5029f2c558f42b0ea10eaa9502c61ad897b9`。

- SDK単体: Ruby 3.3 / 3.4 / 4.0の全3ジョブ成功。各17 tests / 231 assertions、failure / error / skipは0。
- Rails統合: 上記3 Ruby × Rails 8.0 / 8.1の全6ジョブ成功。各1 test / 9 assertions、failure / error / skipは0。各ジョブでSDK Contractも通過。
- 実HTTP: Ruby 3.4でWEBrickを起動し、Agent Card / Echo / GetTask / ListTasks / terminal CancelTaskを成功確認。WORKING TaskのキャンセルはContract Testで別途成功確認。
- Ruby 3.4の解決例: SDK-onlyはjson 3.0.2、Rails 8.0.5.1はjson 2.21.2。Rack 3.2.7、protocol-http 0.72.0。
- 判定: **薄い補完を条件にagent2agentを採用可能**。最初の正式Gem依存制約候補は`~> 2.0.0`。

以下の差分は実行で確認したため、単にSDKをmountするだけで完全互換になるとは扱わない。

## 既に確定した差分

1. **Ruby下限は3.3**。Ruby 3.2.11でBundlerが依存解決に失敗。SDKが要求する`protocol-http ~> 0.62`はRuby>=3.3を要求する。
2. SDKの`A2A.agent`はRack appで、WellKnown / REST / gRPC予約 / JSON-RPCを含む。公開するのはRails側のexact routeに限定する。
3. SDKのTriageはSchema objectを生成するが`valid!`を呼ばない。Adapterでvalidationを明示する。
4. SDK付属のprotobuf由来JSON schemaには`required`宣言がない。`valid!`だけで必須項目やoneof等を保証できない。
5. Version validationはIntegration側で必要。SDKの`VersionNotSupportedError`を使い、SDKにJSON-RPC envelopeの生成を委譲する。
6. Rails 8.0.5.1 + json 3.0.2ではRailsの404 JSON応答が`unknown keyword: quirks_mode`で500になる。Rails 8.0の検証環境のみjson<3を指定する。Rails 8.1はjson 3で検証する。正式Gemの制約・導入ドキュメントへの反映は後続の依存設計で確定する。
7. SDKのTriageはraw Rack envをINFOログへ出力する。Rails envにはsecret_key_base等も含まれるため、正式Adapterではこのログを抑止または安全なloggerへ置換する。
8. Rack 3のinputはrewindを必須としないが、SDK JSON-RPC bindingは無条件にrewindする。実HTTP smokeで500を再現。AdapterでStringIOへ変換し、SDKの前提を満たす。正式実装ではbody size limitも設ける。
9. `ListTasks` / `CancelTask`をv0.1 Scopeへ追加する。同期Handler / Memory Store / Streaming=falseの方針は維持する。

Ruby 3.2の依存解決失敗: [初回CI](https://github.com/cuichangquan/a2a-rails/actions/runs/37430766241)。

## Adapter方針

- `GET /.well-known/agent-card.json`はRails側で生成・公開。
- `POST /a2a`のみSDKへ渡す。内部でSDKのroot pathに変換する。
- HTTP method / JSON Content-TypeをIntegration境界で保証。
- Rack inputをrewind可能なbufferへ正規化。実HTTP smokeでサーバー起動からTask操作まで検証する。
- Versionはheader、またはquery parameterを利用。未指定/空は0.3として拒否。対応は1.0のみ。
- SDK固有Request / Error / Rack envをHandlerへ渡さない。
- Streaming=falseは`UnsupportedOperationError`、Push=falseは`PushNotificationNotSupportedError`。
- キャンセルとHandler完了の競合では、atomicな状態変更によりterminal stateを保持する。
- 実処理の停止や副作用rollbackは別の責務。安全に受理できないキャンセルは拒否できる。

## 実行対象

| 対象 | Ruby | Rails |
|---|---|---|
| SDK Contract | 3.3 / 3.4 / 4.0 | なし |
| Rails Integration | 3.3 / 3.4 / 4.0 | 8.0 / 8.1 |
| 既知除外 | 3.2 | SDK依存解決不能 |

SpikeはSDKのversionを`= 2.0.0`へ完全固定する。推移依存はBundlerのCI実行時に解決される。正式Gemの最初のSDK依存制約は`~> 2.0.0`を採用予定とする。

## 次: Step 15-5 — Gem Skeleton / Protocol Adapter

- Gem skeletonとProtocol Adapterへ、この境界を移す。
- Agent/Skill DSLと汎用Dispatcher、Handler結果のArtifact mappingを実装。
- Task LifecycleのCOMPLETED / FAILED / REJECTED / CANCELEDを統合。
- 付属schemaで不足する必須項目・oneof・値制約とJSON-RPC envelope validationの責務を確定。
- 認証/認可とTask可視性、cursor expiry、production Memory Storeの限界を文書化。
- SDKのraw env loggingを抑止し、Rails 8.0のJSON依存制約を決める。
- Critical E2Eと公式TCKで互換性を広げる。

## 参照

- [A2A v1.0.0 specification](https://a2a-protocol.org/v1.0.0/specification/)
- [Published agent2agent 2.0.0](https://rubygems.org/gems/agent2agent/versions/2.0.0)
- [SDK source inspected at 273f45f](https://github.com/general-intelligence-systems/agent2agent/tree/273f45f6b7358b0b0e76bbc0dcf12395e3cc5963)
- [Spike execution instructions](../../spikes/agent2agent_v1/README.md)

ソース調査だけで互換性を確定せず、CIではRubyGemsから公開済み2.0.0をインストールして実行する。
