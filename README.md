# Orca for Even G2

Even G2 / R1 から Orca のエージェントセッションを操作するアプリです。セッションを選んで進捗を読み、音声やスマートフォンから指示を送り、実行を止められます。

- アプリ本体は **MoonBit** で書いています。画面遷移・表示・API・中継の判断は純粋関数のコア（`core/`）にまとめ、スマートフォン（`app/`）、Mac のブリッジ（`bridge/`）、Cloudflare Worker（`worker/`）は JS FFI の薄いアダプターです。
- インフラは **Terraform** が管理します。Cloudflare の Worker・静的 assets・Tunnel・DNS・Access を一度の `apply` で作ります。
- ツールチェーンとビルドは **Nix** flake にまとめています。

```text
G2 / R1 ─ Even App (WebView: app/) ─ Cloudflare Worker (worker/) ─ Access ─ Tunnel ─ Mac bridge (bridge/) ─ Orca
```

## G2 / R1 の操作

| 画面           | 上下スワイプ                  | タップ                        | ダブルタップ |
| -------------- | ----------------------------- | ----------------------------- | ------------ |
| セッション一覧 | セッションを選ぶ              | 出力を開く                    | 一覧を更新   |
| 出力           | ページ移動（上で追従を一時停止、最終ページで下なら再開） | 操作メニュー | 一覧へ戻る   |
| 操作メニュー   | 項目を選ぶ                    | 決定                          | 出力へ戻る   |
| 送信内容の確認 | ページ移動                    | 次のページ。最終ページで送信  | 取り消し     |
| 停止の確認     | —                             | Ctrl-C を送る                 | 取り消し     |
| 録音中         | —                             | 録音を終えて認識              | 取り消し     |

出力画面で長押しすると録音が始まり、離すと Mac 上の whisper.cpp で文字にします。認識結果は確認画面に出るだけで、タップするまで送信しません。操作メニューからは「続けて」の送信、最新出力への移動、停止も選べます。

スマートフォンの画面には G2 と同じ表示のプレビュー、同じ操作のボタン、指示の入力欄、接続設定があります。入力欄の指示も、G2 か画面のボタンで確認してから送ります。通常のブラウザで開いた場合はプレビューだけで動きます（矢印キー / Enter / Esc でも操作できます）。

## 使い方

### 1. ブリッジを起動する（Mac）

Orca を起動した Mac で実行します。

```sh
nix run .#bridge
```

起動すると **ペアリング用 QR と URL**（`…/#token=…`）をターミナルに表示します。QR または URL は操作権限そのものなので共有しないでください。トークンは初回起動時に生成し、`~/Library/Application Support/even-g2-orca/bridge-token`（権限 0600）に保存します。ビルドしたブリッジを直接起動する場合は `qrencode` を PATH に入れると QR が表示されます。

設定はカレントディレクトリの `.env` から読み込みます（[.env.example](.env.example)）。

### 2a. 同じ LAN で使う

```sh
BRIDGE_HOST=0.0.0.0 nix run .#bridge
```

スマホの Even Realities アプリで G2 を接続します。実機で QR を読み込むには、スマホアプリと同じアカウントで [Even Hub](https://hub.evenrealities.com/login) に開発者としてログインし、アプリを完全終了して開き直す必要があります。その後、アプリの **Even Hub** に現れる開発者用の **Scan QR / Prototype Mode** から、Mac のターミナルに表示された QR を読み取ります。この項目が見えない場合は、先にアカウントとアプリの再起動を確認してください。URL は `http://<Mac の IP>:3210/#token=…` です。通常のスマホブラウザでも開けますが、その場合は G2 に接続しないプレビューになります。LAN 内の通信は HTTP です。

### 2b. Cloudflare 経由で使う

Cloudflare のアカウント・DNS ゾーンと、Workers / Tunnel / Access / DNS を編集できる API トークンが必要です。

1. `infra/example.tfvars.example` を `infra/terraform.tfvars` にコピーし、account ID・zone ID・アプリと bridge のホスト名を設定します。
2. **state に Tunnel token と Access の service token が入る**ので、先に暗号化された private backend を `infra/` に設定してください。state と tfvars は Git に入れません。
3. 配置します。`nix run .#deploy` は Nix でビルドした成果物を Terraform に渡して `apply` します。

   ```sh
   export CLOUDFLARE_API_TOKEN=...
   nix run .#deploy
   ```

4. Mac で bridge を loopback のまま起動し、別のターミナルで Tunnel を張ります。

   ```sh
   BRIDGE_PUBLIC_URL="$(terraform -chdir=infra output -raw app_url)" nix run .#bridge
   nix run .#tunnel
   ```

5. Even Realities アプリの **Even Hub** に現れる開発者用の **Scan QR / Prototype Mode** から、表示された QR を読み取ります。URL は `https://<app_hostname>/#token=…` です。

Worker は `/api/*` だけを Tunnel のホスト名へ中継し、そのときに自分の Access service token を付けます。Access の資格情報・Tunnel token・Orca の RPC トークンはスマートフォンに渡りません。スマートフォンが持つのはペアリング用トークンだけで、これはブリッジが検証します。

## 音声入力（任意）

[whisper.cpp](https://github.com/ggml-org/whisper.cpp) の CLI とモデルを Mac に用意し、`.env` に設定します。

```sh
WHISPER_CLI_PATH=/path/to/whisper-cli
WHISPER_MODEL_PATH=/path/to/ggml-large-v3-turbo.bin
```

G2 のマイク（16 kHz PCM16 mono、最大 60 秒）を WAV にしてブリッジへ送り、Mac 上で認識します。外部の音声認識サービスには送りません。

## 開発

```sh
nix develop                          # moon / node / terraform / cloudflared
moon test --target js                # コアのテスト
scripts/fetch-sdk.sh                 # Even Hub SDK を取得（integrity を検証）
scripts/build.sh                     # dist/ に web・worker・bridge を出力
node dist/bridge/bridge.js           # ビルドしたブリッジを直接起動
nix flake check                      # fmt・テスト・ビルド
```

`nix build` は `result/{web,worker,bridge}` を作ります。Even Hub SDK（MIT）は npm の tarball を integrity 付きで取得し、バンドラーを使わずにそのまま読み込みます。

| ディレクトリ | 内容                                                                 |
| ------------ | -------------------------------------------------------------------- |
| `core/`      | 画面状態機械、G2 表示、折り返し、Orca 応答の解釈、API・中継の判断   |
| `js/`        | 共有の JS FFI（時刻・タイマー・乱数）                                |
| `app/`       | スマートフォン WebView。DOM・保存・HTTP・Even Hub SDK               |
| `bridge/`    | Mac の Node.js ブリッジ。HTTP・Orca のローカル RPC / CLI・whisper   |
| `worker/`    | Cloudflare Worker。assets 配信と API 中継                            |
| `web/`       | HTML / CSS と SDK を読み込む起動スクリプト                           |
| `infra/`     | Terraform（Worker・assets・Tunnel・DNS・Access）                     |
| `nix/`       | MoonBit ツールチェーンと成果物の derivation                          |

設計と互換性の境界は [docs/design.md](docs/design.md) を参照してください。

## 対応範囲

- Orca **1.4.206** の、ターミナル表示のエージェントセッションで確認しています。内部 RPC は公開 SDK ではないため、Orca を更新したら再確認してください。
- native chat 表示、閉じたセッション、質問・権限ダイアログへの回答には対応していません。
- 実機 G2 のフォント・Bluetooth・Even App のバックグラウンド動作は、自動テストの対象外です。
- 送信の重複抑制はブリッジのプロセス内（24 時間）だけです。通信が切れた後は、再送する前に出力を確認してください。
