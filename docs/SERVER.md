# AI連携サーバー（MCP）の作り方

Cloudflare Workers + D1（TypeScript）で作った、Claude から計画と実績を読むためのサーバーです。コードは `server/` にあります。

- **アプリはサーバーなしで完全に動きます。** 同期は、アプリの設定で「AI連携サーバーと同期」をオンにしたときだけ動きます（初期値オフ）。
- **画像はサーバーに送りません。** 送るのは文字起こし・時刻・区分・状態・持ち越し回数・実際の時間だけです（`has_handwriting_image` で「画像があるか」だけ伝えます）。
- **URL について**：サーバーはプログラムが動く場所が必要なので、静的なページしか置けない GitHub Pages には載せられません。Cloudflare が無料でくれる `https://studyplan-mcp.<あなたのアカウント>.workers.dev` を使います。GitHub Pages は、プライバシーポリシーとサポートのページ（`site/`）に使います。

## しくみ

```
iPhone アプリ ──(端末トークン)──▶ /v1/sync/push・pull・DELETE /v1/data ─┐
                                                                          ├─ D1（SQLite）
Claude（カスタムコネクタ）──(OAuth：GitHub ログイン＋許可リスト)──▶ /mcp ─┘
```

| 部分 | ファイル |
|---|---|
| 入口（OAuth で /mcp を守る） | `server/src/index.ts` |
| GitHub ログインと同意画面（許可するアカウントは自分1つ） | `server/src/github-handler.ts` |
| MCP ツール（フェーズA・B） | `server/src/mcp.ts`, `server/src/queries.ts` |
| 同期 API（/v1） | `server/src/sync-api.ts`, `server/src/sync.ts` |
| 表（D1） | `server/migrations/0001_init.sql` |
| 認証なしのローカル確認用 | `server/src/authless.ts`（localhost 以外からは断る） |

### MCP ツール

| フェーズ | ツール | 中身 |
|---|---|---|
| A（読み取り専用・`readOnlyHint`） | `get_day_plan(date)` | 指定日のカード一覧（DayPlanDTO） |
| A | `list_days(from, to)` | 日ごとのカード数と状態別の件数（最大62日） |
| A | `get_review_context(date, days_back)` | 前日までの計画と実績（days_back は最大7、当日は含まない） |
| A | `list_carried_over_cards(since)` | 持ち越しのカード（最大100件、since は90日前まで） |
| B（書き込み。`MCP_ALLOW_WRITES` が `"true"` のときだけ出る） | `update_card_status(card_id, status)` | 状態を記録（アプリは次の同期で受け取る） |
| B | `log_actual_time(card_id, actual_start, actual_end)` | 実際の時間を記録 |

返すのは JSON だけで、解釈・評価・助言は含めません。日付は Asia/Tokyo の `YYYY-MM-DD`、時刻は `HH:mm` です。入力は zod で検証し、ログにカードの文章は出しません。
写真からカードを作る道具・要約や助言の道具・削除の道具は作りません。

### 同期 API

| API | 中身 |
|---|---|
| `POST /v1/sync/push` | 変更分をまとめて送る（アプリは500件ずつに分けて送る。サーバーの上限は表ごとに2000件）。`updated_at` が新しいときだけ上書きするので、同じ内容を2回送っても結果は同じ（冪等） |
| `GET /v1/sync/pull?since=` | 前回の `cursor` より後に受け取った変更を返す。返ってきた `cursor` を次の `since` に使う。表ごとに最大2000件で、続きがあれば `has_more: true`（アプリは続けて呼ぶ）。書き込み途中のものを取りこぼさないよう、受け取ってから2秒たった変更だけを返す |
| `DELETE /v1/data` | 自分の全データを削除する |

競合したら `updated_at` が新しい方を採用します。サーバーで書き込むときは、既存より必ず新しい `updated_at` を付けます。

## 作る順番（設計の「6. 作る順番」を補ったもの）

> 元の指示は「1. authless テンプレートで /mcp が動くことを、ローカルのみで MCP Inspector を…」で途切れていたので、2 以降は私の判断で補いました。

### 1. 認証なしで /mcp が動くことを、ローカルだけで確かめる

```sh
cd server
npm install
npx wrangler d1 migrations apply studyplan-local --local --env authless
npm run dev:authless                     # http://localhost:8787 で起動
npx @modelcontextprotocol/inspector      # 別のターミナルで。Transport: Streamable HTTP、URL: http://localhost:8787/mcp
```

Inspector の Tools でツールが6つ見え、`get_day_plan` を呼べたら OK です。この形は**公開しません**（localhost 以外からは 403 になります）。

### 2. Cloudflare に D1 と KV を作る

```sh
npx wrangler login
npx wrangler d1 create studyplan          # 表示された database_id を wrangler.jsonc に書く
npx wrangler kv namespace create OAUTH_KV # 表示された id を wrangler.jsonc に書く
npm run db:migrate:remote
```

### 3. GitHub でのログイン（OAuth）を用意し、許可を自分1人に絞る

1. GitHub の Settings → Developer settings → OAuth Apps → New OAuth App
   - Homepage URL：`https://studyplan-mcp.<あなたのアカウント>.workers.dev`
   - Authorization callback URL：`https://studyplan-mcp.<あなたのアカウント>.workers.dev/callback`
2. Client ID と Client secret を登録する
   ```sh
   npx wrangler secret put GITHUB_CLIENT_ID
   npx wrangler secret put GITHUB_CLIENT_SECRET
   ```
3. `wrangler.jsonc` の `PUBLIC_URL` を自分の URL に、`ALLOWED_GITHUB_LOGINS` を自分の GitHub のユーザー名にする

### 4. 端末トークンを作る

```sh
npm run token:new
npx wrangler secret put DEVICE_TOKEN_HASHES   # 表示された「ハッシュ」を貼る
```

表示された「トークン」は、iPhone の 設定 → AI連携サーバー → APIトークン に貼ります（Keychain に保存されます）。

### 5. 公開して、フェーズA（読み取り専用）で使う

```sh
npm run deploy
```

- アプリの設定で「AI連携サーバーと同期」をオンにし、URL を入れて「今すぐ同期」
- Claude の 設定 → コネクタ → カスタムコネクタを追加 で `https://…workers.dev/mcp` を入れる → GitHub でログイン（許可リストのアカウントだけ通ります）

### 6. フェーズB（書き込み）を使うとき

`wrangler.jsonc` の `MCP_ALLOW_WRITES` を `"true"` にして `npm run deploy`。Claude で記録した状態や時間は、アプリが次に同期したとき（アプリを開いたとき、または「今すぐ同期」）に反映されます。

## テスト

```sh
cd server
npm run typecheck
npm test     # node:sqlite を D1 の代わりに使い、本番と同じマイグレーションで表を作って確かめる
```

## 設計からの小さな追加

- 各表に `synced_at`（サーバーが受け取った時刻）を足しました。`pull` の目印（表ごとに「最後に渡した行の synced_at と id」）に使い、端末の時計のずれや件数の多さで取りこぼさないためです。
- DayPlanDTO のカードに `category` を足しました（D1 の cards.category と同じ値）。
- SSE（`/sse`）は作らず、Streamable HTTP（`/mcp`）だけにしました。Claude のカスタムコネクタは Streamable HTTP に対応しています。
- 1人用のサーバーなので、表に「持ち主」の列はありません。`DELETE /v1/data` は全行を消します。
