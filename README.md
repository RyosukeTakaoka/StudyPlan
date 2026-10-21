# 手書きボード（StudyPlan）

紙やホワイトボードに書いた予定を撮影して、**自分の筆跡のまま**カードにする iPhone・iPad アプリです。
「今」と「次」をウィジェットで見て、ワンタップで実績を残し、必要なときだけ AI（Claude）に計画と実績を渡します。

- 設計書：[docs/DESIGN.md](docs/DESIGN.md)
- UI の約束ごとと確認リスト：[docs/UI_GUIDELINES.md](docs/UI_GUIDELINES.md)
- AI連携サーバー（MCP）の作り方：[docs/SERVER.md](docs/SERVER.md)
- UI のコンセプト画像：[docs/ui-concept.png](docs/ui-concept.png)

## フォルダの中身

| フォルダ | 中身 |
|---|---|
| `StudyPlan.xcodeproj` | Xcode のプロジェクト。`git pull` したらこれを開く |
| `App/` | アプリ本体（画面・データ・処理） |
| `Shared/` | アプリとウィジェットの両方で使う部品（色・区分・時刻・ウィジェット用データ・DayPlanDTO） |
| `Widget/` | ウィジェット「今→次」 |
| `Config/` | Info.plist と権限設定（entitlements） |
| `cloudkit/schema.ckdb` | iCloud（CloudKit）のスキーマ |
| `server/` | AI連携サーバー（Cloudflare Workers + D1、TypeScript） |
| `site/` | GitHub Pages で公開するページ（プライバシーポリシー・サポート） |

## 開き方（初めての人向け）

1. `git pull` で最新にする
2. `StudyPlan.xcodeproj` をダブルクリックして Xcode で開く（Xcode 16 以降。フォルダ同期の形式を使っているため）
3. 左の一覧でいちばん上の「StudyPlan」→ TARGETS の「StudyPlan」と「StudyPlanWidget」それぞれの **Signing & Capabilities** で、Team に自分の Apple Developer アカウントを選ぶ
4. 上の実行先で iPhone（実機かシミュレーター）を選び、▶ ボタンで実行する
5. 最初は「サンプルで試す」を押すと、合成した筆跡で動きを確認できます

> **注意**：App Groups（ウィジェットとデータを共有）と iCloud（端末間同期）は、有料の Apple Developer Program のアカウントで使えます。
> バンドルIDは `com.ryosuketakaoka.studyplan` にしてあります。ほかの人がすでに使っていて登録できないと言われたら、
> 次の4か所を同じ新しい名前に変えてください：プロジェクトの `PRODUCT_BUNDLE_IDENTIFIER`（2ターゲット）、
> `Config/*.entitlements` の App Group と iCloud コンテナ、`Shared/WidgetPayload.swift` の `appGroupID`、
> `App/Models/AppModelContainer.swift` の `cloudKitContainerID`。

## 版ごとの機能（設計書の v0.1〜v0.3 まで実装済み）

| 版 | 機能 | 主なファイル |
|---|---|---|
| v0.1 | 定点撮影（前回写真を30%で重ねる・枠の検出と台形補正） | `App/Features/Capture/`, `App/Services/BoardProcessor.swift` |
| v0.1 | カードの切り出し（文字認識の位置から提案 → 確認画面で直す） | `BoardProcessor.swift`, `App/Features/Confirm/` |
| v0.1 | 実績チェック（完了／未完了／持ち越し／スキップ）と持ち越し回数 | `App/Models/Card.swift`, `App/Components/CardViews.swift` |
| v0.1 | ウィジェット「今→次」（インクの領域を切り出し＋タイトルの文字） | `Widget/`, `App/Services/WidgetSync.swift` |
| v0.2 | 並べて比較（同じボードの別の日を同じ大きさで） | `App/Features/Compare/` |
| v0.2 | 時間ログ（開始・終了をワンタップ） | `App/Models/TimeLog.swift` |
| v0.2 | 筆跡のまま検索（一致した行を画像の上に重ねる） | `App/Features/Search/` |
| v0.2 | 検索できる PDF の書き出し（日・週・月） | `App/Services/PDFExporter.swift` |
| v0.2 | App Intents（ショートカット・Siri・AI 向けの口） | `App/Intents/AppIntents.swift` |
| v0.3 | 見返しのきっかけ通知（週1回・答えを見る前に思い出す） | `App/Services/ReviewReminder.swift`, `App/Features/Review/` |
| v0.3 | iCloud 同期（設定でオンにしたときだけ） | `App/Models/AppModelContainer.swift`, `cloudkit/schema.ckdb` |
| v0.3 | MCP サーバーと同期 API（設定でオンにしたときだけ） | `server/`, `App/Services/ServerSync.swift` |
| v0.3 | TestFlight で配る | 手順は下の「TestFlight」 |

## データの持ち方

- 全モデル（Board / Snapshot / Card / TimeLog）に `id`（端末で作る UUID）・`updatedAt`・`deletedAt`（論理削除）があります。
- アプリはサーバーなしで完全に動きます。**iCloud 同期と AI連携サーバーは、どちらも設定でオンにしたときだけ**動きます（初期値はオフ）。
- AI に渡す形は `DayPlanDTO` の1つだけ。App Intents と MCP で同じ形です（`Shared/DayPlanDTO.swift` と `server/src/dto.ts`）。

## iCloud（CloudKit）のスキーマ

`cloudkit/schema.ckdb` は、SwiftData が CloudKit に保存するときの形（`CD_` で始まる名前）を書いたものです。

1. 開発用の環境で一度アプリを動かし、設定で「iCloudで端末間を同期」をオンにして開き直すと、CloudKit 側に同じ形が自動で作られます
2. 本番に出す前に、`xcrun cktool export-schema` で書き出した内容とこのファイルを見比べ、違いがあれば書き出した方を正としてこのファイルを更新してください
3. CloudKit Console の「Deploy Schema Changes」で本番に反映します

## TestFlight

1. Xcode のメニュー Product → Archive
2. Organizer で「Distribute App」→「TestFlight & App Store」
3. App Store Connect の TestFlight で、外部テスター（3〜5人）を追加
4. プライバシーポリシーの URL には GitHub Pages のページを使います：
   `https://ryosuketakaoka.github.io/StudyPlan/privacy.html`
   （初回だけ、GitHub のリポジトリの Settings → Pages → Source を「GitHub Actions」にしてください。`main` ブランチの `site/` が公開されます）

## テスト

- サーバー：`cd server && npm install && npm run typecheck && npm test`（GitHub Actions でも自動で走ります）
- アプリ：Xcode のプレビュー（`TodayView.swift` の下にライト／ダーク・大きな文字のプレビューがあります）と、[docs/UI_GUIDELINES.md](docs/UI_GUIDELINES.md) の確認リスト
