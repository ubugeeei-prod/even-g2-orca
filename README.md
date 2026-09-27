# Orca for Even G2

Even G2 / R1 から Orca の進捗と返答を読むアプリ。セッションの切り替え、ページ移動、最新出力の追従、一時停止を中心に、指示の送信と実行の停止を確認付きで行えます。

MoonBit の純粋関数で表示と入力遷移を実装し、TypeScript 7 の関数ベースのアダプターで Even Hub SDK・HTTP・Orca に接続します。Mac のブリッジは Node.js の型除去で直接実行します。開発・lint・format・テストは Vite+ (`vp`) に統一しています。

## 最初に起動する

必要なものは Node.js（`.node-version`）、Vite+、公式 MoonBit toolchain、起動中の Orca です。Orca **1.4.206** のターミナル形式の agent session で読み取りを確認しています。MoonBit の実行ファイルを別の場所に入れた場合は `MOON_BIN` を指定してください。

```sh
vp install --frozen-lockfile
cp .env.example .env
vp build
vp run bridge
```

Mac とスマートフォンを同じ LAN に接続し、ブリッジが表示する URL を開いてください。URL の fragment にあるペアリング用トークンを読み取ると、画面がセッション一覧を表示します。fragment は読み取り後に履歴から除き、トークンは端末の localStorage に保存します。QR と URL は操作権限を含むため共有しないでください。

Even App の開発用 URL / QR 読み込みから同じページを開くと、公式 SDK が G2 へ接続します。普通のブラウザでは同じ操作をプレビューできます。実機の接続方法は [Even Hub のドキュメント](https://hub.evenrealities.com/) に従ってください。

LAN 接続で Mac のブリッジへ直接アクセスするときは、HTTP を使います。インターネットからの利用には、以下の Cloudflare 構成で HTTPS を使ってください。

## G2 / R1 の操作

| 画面           | Swipe                        | Tap                        | Double tap |
| -------------- | ---------------------------- | -------------------------- | ---------- |
| セッション一覧 | セッションを選択             | 出力を開く                 | 一覧を更新 |
| 進捗・返答     | ページ移動して追従を一時停止 | 操作メニュー               | 一覧へ戻る |
| 操作メニュー   | 操作を選択                   | 決定                       | 出力へ戻る |
| 指示の確認     | 指示のページを移動           | 次ページ、最終ページで送信 | キャンセル |
| 停止の確認     | —                            | 停止入力を送信             | キャンセル |
| 録音           | —                            | 録音終了、認識後に確認     | 録音取消   |

出力画面で長押しすると録音を開始し、離すと終了します。音声は任意機能です。`WHISPER_CLI_PATH` と `WHISPER_MODEL_PATH` に [whisper.cpp](https://github.com/ggml-org/whisper.cpp) の CLI とローカルモデルの絶対パスを設定してください。音声は Mac 上で認識し、確認するまで指示を送信しません。

ブラウザには接続設定、G2 表示プレビュー、指示の入力欄、入力シミュレーションもあります。出力は標準設定で 2 秒ごとに取得します。閲覧を一時停止すると表示中のスナップショットを固定し、追従を再開すると最新ページへ進みます。

## Cloudflare に配置する

```text
Even App → Worker + static assets → Access → Tunnel → Mac bridge → Orca
```

Terraform は Tunnel / DNS / Access / service token を管理し、Wrangler は Worker と assets を管理します。Cloudflare のアカウントと DNS zone、`cloudflared`、Terraform が必要です。Terraform の service token は state に保存されるため、**apply 前に private backend を設定**してください。state と `.tfvars` は Git に追加しません。

1. `infra/example.tfvars.example` を `infra/terraform.tfvars` にコピーし、account ID・zone ID・ブリッジ用 hostname を設定します。Cloudflare provider の認証は `CLOUDFLARE_API_TOKEN` などの環境変数で渡します。

   ```sh
   terraform -chdir=infra init
   terraform -chdir=infra plan
   terraform -chdir=infra apply
   ```

2. `wrangler.jsonc` の `vars.ORCA_BRIDGE_ORIGIN` を `terraform -chdir=infra output -raw bridge_origin` の値に設定します。複数の Cloudflare アカウントを使う場合は Wrangler の `account_id` も指定します。通常の Web URL での利用は同じ origin で完結します。

   ```sh
   vp build
   vp exec wrangler deploy
   terraform -chdir=infra output -raw access_client_id | vp exec wrangler secret put ACCESS_CLIENT_ID
   terraform -chdir=infra output -raw access_client_secret | vp exec wrangler secret put ACCESS_CLIENT_SECRET
   ```

3. Mac の `.env` に `BRIDGE_HOST=127.0.0.1` と `BRIDGE_PUBLIC_URL=https://YOUR-WORKER.workers.dev` を設定します。公開 URL は **Worker の URL**、Worker の中継先は **Tunnel の hostname** です。別々のターミナルで起動します。

   ```sh
   vp run bridge
   ```

   ```sh
   TUNNEL_TOKEN="$(terraform -chdir=infra output -raw tunnel_token)" cloudflared tunnel run
   ```

4. ブリッジのペアリング用 URL を Even App から開きます。Worker は自分の Access service token を付けて Mac へ中継し、Mac は別の user pairing token を検証します。Access / Tunnel / Orca RPC の資格情報をスマートフォンへ渡しません。

Access service token の有効期限は `service_token_duration` で設定できます。初期値は 1 年です。期限前に Terraform 側で更新し、Wrangler の 2 つの secret も更新してください。ペアリング用トークンを更新する場合はブリッジを止めて `.local/bridge-token` を退避し、再起動・再ペアリングします。

## Even Hub パッケージ

```sh
vp run pack -- https://YOUR-WORKER.workers.dev
```

`even-g2-orca.ehpk` を生成します。指定した origin を初期接続先と network permission の whitelist に反映し、SDK バージョンと対応 Even App バージョンを公式 CLI で検証します。ユーザーのトークンや Cloudflare の secret は含めません。`app.json` が manifest の元で、`app.local.json` と `.ehpk` は生成物です。

パッケージの WebView が Worker と異なる origin で動く場合は、その **実際の origin** を `wrangler.jsonc` の `vars.ALLOWED_ORIGINS` に指定し、再配置してください。comma 区切りで指定でき、初期状態は同じ origin のみ許可します。opaque origin の `null` は必要と確認した場合だけ明示します。パッケージの接続設定に user pairing token を入力してください。LAN のブリッジへ直接接続するパッケージは Mac 側の `BRIDGE_ALLOWED_ORIGINS` も設定します。

## 設定

環境変数は [.env.example](.env.example) を参照してください。表示サイズ・更新周期・データ上限は [shared/config.ts](shared/config.ts)、設計と互換性の境界は [docs/design.md](docs/design.md) にまとめています。

| 変数                                                         | 用途                                                   |
| ------------------------------------------------------------ | ------------------------------------------------------ |
| `BRIDGE_HOST`, `BRIDGE_PORT`                                 | Mac の listen address。Cloudflare 利用時は loopback    |
| `BRIDGE_PUBLIC_URL`                                          | ユーザーが開く URL。未指定なら Mac の LAN address      |
| `BRIDGE_TOKEN`                                               | 任意の pairing token。未指定なら安全な乱数で生成・保存 |
| `BRIDGE_ALLOWED_ORIGINS`                                     | 別 origin のパッケージ / 開発ページの許可先            |
| `ORCA_CLI_PATH`, `ORCA_USER_DATA_PATH`                       | Orca の CLI と profile の検出を上書き                  |
| `WHISPER_CLI_PATH`, `WHISPER_MODEL_PATH`, `WHISPER_LANGUAGE` | 任意のローカル音声認識                                 |
| `MOON_BIN`                                                   | MoonBit compiler の実行ファイル                        |

## 開発と検証

```sh
vp run bridge
vp dev
```

別 port の開発ページを使う場合は `.env` の `BRIDGE_ALLOWED_ORIGINS` にその origin（例 `http://localhost:5173`）を追加してください。`vp dev` の `/api` は Mac のブリッジへ proxy します。

```sh
moon fmt --check
moon test --target js --deny-warn
vp check
vp test run
vp build
vp exec playwright install chromium
vp run test:e2e
vp exec wrangler deploy --dry-run
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
terraform -chdir=infra test
```

GitHub Actions は同じ検証を実行し、Terraform は実リソースを作らない mock plan で検証します。Playwright の desktop / mobile テストは独立した fixture bridge を使い、実際の Orca に指示や停止入力を送りません。

現在の対象は **Orca のターミナル形式の agent session** です。native chat、閉じた過去の session、質問・権限ダイアログへの回答は未対応です。内部 RPC の互換性は Orca の更新時に再確認してください。実機 G2 の Bluetooth、フォント、Even App の background 動作と、実際の Cloudflare 配置は自動テストの対象外です。

操作後に通信が切れた場合は、再送する前に出力を確認してください。重複抑制は Mac のブリッジプロセス内の保持期間に限定され、再起動をまたぐ配送保証はありません。
