# Security policy / セキュリティポリシー

## Reporting a vulnerability / 脆弱性の報告

**Please do not post working exploits, credentials, sensitive payloads or undisclosed vulnerability details in public GitHub Issues or PRs.**

**脆弱性の詳細や再現コード、認証トークン、秘密情報は公開Issue・PRに書かないでください。**

1. Prefer GitHub's [private vulnerability report](https://github.com/cuichangquan/a2a-rails/security/advisories/new) **if the repository has enabled that feature and the form is available**. This repository's actual Private vulnerability reporting configuration has **not been verified by this policy**.
2. If that private form is unavailable, contact the maintainer via their [GitHub profile](https://github.com/cuichangquan) **to request a confidential communication channel without including exploit details**. Do not assume public Issues are private.
3. Include the affected published Gem version, relevant Rails/Ruby versions, impact and a minimal reproduction **only through the confidential channel**. Maintainers will assess severity, reproduce, remediate and coordinate disclosure when feasible.

1. GitHubの[非公開の脆弱性報告フォーム](https://github.com/cuichangquan/a2a-rails/security/advisories/new)が**有効な場合は**そちらを使用してください（現時点で機能の有効状態は未確認）。
2. フォームが利用できない場合は、[メンテナーのGitHubプロフィール](https://github.com/cuichangquan)から**非公開の連絡手段の案内を依頼**してください。公開Issueに脆弱性の具体的な内容を投稿しないでください。
3. Gemの対象バージョン、影響、Rails/Rubyバージョン、最小再現例は**非公開の連絡手段でのみ**共有してください。

## Supported versions / 対象バージョン

- **Published stable:** `a2a-rails 0.2.0`.
- **Unpublished source candidate:** `0.3.0` is **not** a RubyGems release. The Step 31-5 candidate may be downloaded from controlled CI but must not be represented as published or production-certified. Its hash and supported dependency set require explicit Step 31-6 owner release approval.
- **Published pre-release:** [`0.3.0.rc1`](https://rubygems.org/gems/a2a-rails/versions/0.3.0.rc1), including the outbound Client. The [publication record](docs/release/v0.3.0-rc1-publication-record.md) documents exact artifact verification and limits. RC1 checks do not confer production endorsement; stable `0.3.0` remains unreleased.
- Older versions may lack security hardening present in `0.2.0`. Users should prefer the latest **published stable** version appropriate to their application and review the [CHANGELOG](CHANGELOG.md) and [upgrade guide](docs/release/upgrading-v0.1.0-to-v0.2.md).
- A precise long-term security support and patch SLA **is not promised** for this volunteer-maintained OSS Gem.

## Security guarantees and limits / 保証範囲と制約

The Gem includes automated security regressions and documented transport/authentication boundaries, but **has not been independently security-audited or certified**. The [optional independent review invitation #113](https://github.com/cuichangquan/a2a-rails/issues/113) is **not an identified vulnerability, not proof of an active incident, and not a mandatory Gem-release blocker**.

Using a published Gem in a production Rails application requires **application- and infrastructure-owned** identity-provider validation, business authorization, bounded access/cost/concurrency, durable store/worker operation and logging/security operations. **Publishing a package does not approve an anonymously exposed public A2A endpoint.** See [production guidance](docs/guides/production-security.md) and [deployment Issue #11](https://github.com/cuichangquan/a2a-rails/issues/11).

[Current Gem release policy](docs/release/step-29-5u-risk-based-oss-release-policy.md): security test and artifact evidence, no known unresolved Critical/High defects and **explicit maintainer GO** are required; a separate third-party review is recommended but optional.

**日本語要約：** CIやセキュリティテストは実施していますが、第三者による独立セキュリティ監査は受けておらず、安全性の認証も取得していません。独立レビュー募集[#113](https://github.com/cuichangquan/a2a-rails/issues/113)は既知の脆弱性報告ではありません。Gemを本番で使用する場合は、認証・業務権限・アクセス制限・永続化・ログ監視などをホストアプリ側で適切に設計してください。
