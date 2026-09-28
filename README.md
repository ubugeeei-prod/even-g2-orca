# Orca for Even G2

Control Orca agent sessions from Even G2 / R1. Select a session, read its recent output, and send a prompt or stop a run after confirmation.

- The app is written in **MoonBit**. Pure functions in `core/` handle navigation, display text, API rules, and relay decisions. The phone app (`app/`), Mac bridge (`bridge/`), and Cloudflare Worker (`worker/`) are thin JavaScript FFI adapters.
- **Terraform** manages the Cloudflare Worker, static assets, Tunnel, DNS, and Access configuration.
- **Nix** provides the toolchain and builds.

```text
G2 / R1 ─ Even App (WebView: app/) ─ Cloudflare Worker (worker/) ─ Access ─ Tunnel ─ Mac bridge (bridge/) ─ Orca
```

## G2 / R1 controls

| Screen | Swipe up / down | Tap | Double tap |
| --- | --- | --- | --- |
| Sessions | Select a session | Open its output | Refresh the list |
| Output | Move between pages; swiping up pauses live updates, and swiping down on the last page resumes them | Open the action menu | Return to sessions |
| Action menu | Select an action | Confirm the selection | Return to output |
| Prompt review | Move between pages | Advance; send from the final page | Cancel |
| Stop review | — | Send Ctrl-C | Cancel |
| Recording | — | Stop recording and transcribe | Cancel |

The glasses show up to four useful output lines at a time. Blank terminal lines and decorative rules are omitted. When voice input is configured, hold on the output screen to record; release to transcribe with whisper.cpp on the Mac. A transcript appears on a review screen and is sent only after a tap. The action menu also offers a short continue instruction, a jump to the latest output, and a stop action.

The phone shows a preview of the G2 display, matching gesture buttons, a prompt field, and connection settings. Prompts entered on the phone still require confirmation on the G2 or with the preview controls. In a regular browser, the page works as a preview without connecting to the glasses; Arrow keys, Enter, and Esc provide keyboard controls.

## Getting started

### 1. Prepare the Mac

Start Orca on the Mac, then start the bridge using the LAN or Cloudflare instructions below. A plain `nix run .#bridge` listens on `127.0.0.1`, which phones cannot reach.

When configured with a phone-reachable URL, the bridge prints a **pairing QR code and URL** (`…/#token=…`) in the terminal. This link grants control of the bridge, so keep it private. On first launch, the bridge creates a token at `~/Library/Application Support/even-g2-orca/bridge-token` with mode `0600`. If you run the built bridge directly, put `qrencode` on your `PATH` to print the QR code.

The bridge loads settings from `.env` in the current directory; see [.env.example](.env.example).

### 2a. Use the same LAN

```sh
BRIDGE_HOST=0.0.0.0 nix run .#bridge
```

Stop an existing bridge with `Ctrl-C` before restarting it. A QR URL beginning with `http://127.0.0.1:3210/` cannot be opened from a phone. The URL should instead begin with `http://<Mac LAN IP>:3210/`.

Connect the G2 in the Even Realities phone app. To scan a development QR code on real hardware, sign in to [Even Hub](https://hub.evenrealities.com/login) with the same account as the phone app, then fully quit and reopen the app. In the app's **Even Hub** section, open **Scan QR / Prototype Mode** and scan the QR code from the Mac terminal. If that option is missing, check the account and restart the app. The pairing URL has the form `http://<Mac LAN IP>:3210/#token=…`.

You can open the URL in a normal phone browser to use the preview, but it will not connect to the G2. LAN traffic uses HTTP.

### 2b. Use Cloudflare

You need a Cloudflare account, a DNS zone, and an API token that can edit Workers, Tunnel, Access, and DNS resources.

1. Copy `infra/example.tfvars.example` to `infra/terraform.tfvars`. Set the account ID, zone ID, app hostname, and bridge hostname.
2. Configure an encrypted private Terraform backend in `infra/` before applying. **Terraform state contains the Tunnel token and Access service token.** Do not commit state or tfvars files.
3. Deploy. `nix run .#deploy` passes the Nix-built assets to Terraform and runs `apply`.

   ```sh
   export CLOUDFLARE_API_TOKEN=...
   nix run .#deploy
   ```

4. Keep the Mac bridge on loopback and start the Tunnel in a separate terminal.

   ```sh
   BRIDGE_PUBLIC_URL="$(terraform -chdir=infra output -raw app_url)" nix run .#bridge
   nix run .#tunnel
   ```

5. In the Even Realities app, open **Even Hub → Scan QR / Prototype Mode** and scan the QR code. The URL has the form `https://<app_hostname>/#token=…`.

The Worker forwards only `/api/*` to the Tunnel and attaches its own Access service token. The phone receives neither Access credentials, the Tunnel token, nor the Orca RPC token. It stores only the pairing token, which the bridge validates.

## Voice input (optional)

Install the [whisper.cpp](https://github.com/ggml-org/whisper.cpp) CLI and a model on the Mac, then configure them in `.env`:

```sh
WHISPER_CLI_PATH=/path/to/whisper-cli
WHISPER_MODEL_PATH=/path/to/ggml-large-v3-turbo.bin
```

The bridge receives up to 60 seconds of 16 kHz, mono PCM16 audio from the G2 as WAV and transcribes it locally on the Mac. Audio is not sent to an external speech recognition service.

## Development

```sh
nix develop                          # moon / node / terraform / cloudflared
moon test --target js                # core tests
scripts/fetch-sdk.sh                 # fetch and verify the Even Hub SDK
scripts/build.sh                     # build web, worker, and bridge into dist/
node dist/bridge/bridge.js           # run the built bridge directly
nix flake check                      # formatting, tests, and build
```

`nix build` creates `result/{web,worker,bridge}`. The Even Hub SDK (MIT) is fetched from npm with a pinned integrity hash and loaded without a bundler.

| Directory | Purpose |
| --- | --- |
| `core/` | Reader state machine, G2 frames, text wrapping, Orca response parsing, API and relay rules |
| `js/` | Shared JavaScript FFI for time, timers, and random IDs |
| `app/` | Phone WebView, DOM, local storage, HTTP, and Even Hub SDK integration |
| `bridge/` | Mac Node.js bridge, HTTP, local Orca RPC / CLI, and whisper.cpp |
| `worker/` | Cloudflare Worker asset serving and API relay |
| `web/` | HTML, CSS, and SDK boot script |
| `infra/` | Terraform for Workers, assets, Tunnel, DNS, and Access |
| `nix/` | MoonBit toolchain and build derivations |

Architecture and compatibility boundaries are documented in [docs/design.md](docs/design.md).

## Current scope

- Tested against terminal-based agent sessions in Orca **1.4.206**. Its internal RPC is not a public SDK, so retest after updating Orca.
- Native chat views, closed sessions, and responses to question or permission dialogs are not supported.
- Automated tests do not cover the real G2 font, Bluetooth, or Even App behavior in the background.
- Duplicate delivery protection lasts 24 hours within one bridge process. After a connection failure, check the output before sending an instruction again.
