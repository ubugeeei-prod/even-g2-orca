#!/usr/bin/env bash
# Download the pinned Even Hub SDK into vendor/ after verifying its integrity.
# `nix build` does the same with fetchurl, so this is only for non-Nix setups.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/sdk.env
source "$root/scripts/sdk.env"

work="$(mktemp -d "${TMPDIR:-/tmp}/even-hub-sdk.XXXXXX")"
trap 'rm -rf "$work"' EXIT
curl -fsSL "$EVEN_HUB_SDK_URL" -o "$work/sdk.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$work/sdk.tgz" | openssl base64 -A)"
if [ "$actual" != "$EVEN_HUB_SDK_INTEGRITY" ]; then
  echo "Even Hub SDK integrity mismatch: $actual" >&2
  exit 1
fi
tar -xzf "$work/sdk.tgz" -C "$work"
mkdir -p "$root/vendor"
cp "$work/package/dist/index.js" "$root/vendor/even_hub_sdk.js"
cp "$work/package/LICENSE" "$root/vendor/even_hub_sdk.LICENSE"
echo "vendor/even_hub_sdk.js ($EVEN_HUB_SDK_VERSION)"
