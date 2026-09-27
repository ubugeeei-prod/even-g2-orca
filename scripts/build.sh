#!/usr/bin/env bash
# Compile the MoonBit packages and assemble the deployable tree:
#
#   <out>/web/      phone WebView (served by the Worker and the bridge)
#   <out>/worker/   Cloudflare Worker module
#   <out>/bridge/   Node.js bridge for the Mac
#
# EVEN_HUB_SDK may point at the SDK's dist/index.js; otherwise vendor/ is used.
# MOON selects the MoonBit CLI (default: moon on PATH).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/dist}"
sdk="${EVEN_HUB_SDK:-$root/vendor/even_hub_sdk.js}"
if [ ! -f "$sdk" ]; then
  echo "Even Hub SDK not found at $sdk. Run scripts/fetch-sdk.sh (or use nix build)." >&2
  exit 1
fi

"${MOON:-moon}" -C "$root" build --target js --release
build="$root/_build/js/release/build"

rm -rf "$out"
mkdir -p "$out/web" "$out/worker" "$out/bridge"

cp "$root/web/index.html" "$root/web/boot.js" "$root/web/style.css" "$out/web/"
cp "$build/app/app.js" "$out/web/app.js"
cp "$sdk" "$out/web/even_hub_sdk.js"

# Workers need an ES module with a default export; the MoonBit main registers
# its handler on globalThis.
{
  cat "$build/worker/worker.js"
  printf '\nexport default { fetch: (request, env, ctx) => globalThis.__orcaFetch(request, env, ctx) };\n'
} > "$out/worker/worker.js"

cp "$build/bridge/bridge.js" "$out/bridge/bridge.js"
echo "Built $out"
