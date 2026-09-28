# Re-pin the rolling MoonBit `latest` artifacts in nix/moonbit.lock.json.
set -euo pipefail
lock=nix/moonbit.lock.json
[ -f "$lock" ] || { echo "Run from the repository root." >&2; exit 1; }
prefetch() { nix store prefetch-file --json "$1" | jq -r .hash; }
base="$(jq -r .moonbit.baseUrl "$lock")"
next="$(jq --arg core "$(prefetch "$(jq -r .moonbit.coreUrl "$lock")")" '.moonbit.coreHash = $core' "$lock")"
for system in $(jq -r '.moonbit.platforms | keys[]' "$lock"); do
  asset="$(jq -r --arg s "$system" '.moonbit.platforms[$s].asset' "$lock")"
  hash="$(prefetch "$base/$asset")"
  next="$(jq --arg s "$system" --arg h "$hash" '.moonbit.platforms[$s].hash = $h' <<<"$next")"
done
next="$(jq --arg d "$(date -u +%Y-%m-%d)" '.moonbit.date = $d | .moonbit.version = "latest@" + $d' <<<"$next")"
printf '%s\n' "$next" > "$lock"
echo "Updated $lock"
