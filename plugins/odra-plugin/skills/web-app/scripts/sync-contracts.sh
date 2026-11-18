#!/usr/bin/env bash
# Copy the addresses of the deployed contracts to the web app.
# Usage: sync-contracts.sh [web-dir]        (default: web)
# Run from the Odra project root after every deploy. For each resources/<chain>-contracts.toml
# the Odra CLI wrote, writes <web-dir>/public/contracts.<chain>.json in the format the generated
# client loads with `Contracts.fromPath`.
set -euo pipefail

WEB_DIR="${1:-web}"
[ -f Odra.toml ] || { echo "Error: run this from the Odra project root (no Odra.toml here)." >&2; exit 1; }
[ -d "$WEB_DIR" ] || { echo "Error: $WEB_DIR does not exist." >&2; exit 1; }
mkdir -p "$WEB_DIR/public"

FOUND=0
for TOML in resources/*-contracts.toml; do
  [ -f "$TOML" ] || continue
  FOUND=1
  CHAIN=$(basename "$TOML" -contracts.toml)
  OUT="$WEB_DIR/public/contracts.$CHAIN.json"
  awk '
    function flush() { if (name != "") { printf "%s    {\"name\": \"%s\", \"package_hash\": \"%s\"}", sep, name, hash; sep = ",\n" } name = ""; hash = "" }
    function value(line) { sub(/^[^=]*=[ \t]*"/, "", line); sub(/"[ \t]*$/, "", line); return line }
    BEGIN { updated = "1970-01-01T00:00:00Z" }
    /^last_updated[ \t]*=/ { updated = value($0) }
    /^\[\[contracts\]\]/ { if (!started) { printf "{\n  \"last_updated\": \"%s\",\n  \"contracts\": [\n", updated; started = 1 } flush() }
    /^name[ \t]*=/ { name = value($0) }
    /^package_hash[ \t]*=/ { hash = value($0) }
    END { if (!started) { printf "{\n  \"last_updated\": \"%s\",\n  \"contracts\": [\n", updated } flush(); print "\n  ]\n}" }
  ' "$TOML" > "$OUT"
  echo "$OUT: $(grep -c '"name"' "$OUT") contract(s)" >&2
done
if [ "$FOUND" -eq 0 ]; then
  echo "Error: no resources/<chain>-contracts.toml found. Deploy the contracts first." >&2
  exit 1
fi
