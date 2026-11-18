#!/usr/bin/env bash
# Create the web app of an Odra project from the plugin's template.
# Usage: new-web-app.sh <Contract> ["Page title"]
#   <Contract>  the main contract of the page, as named in Odra.toml (e.g. DailyAuction)
# Run from the Odra project root. Creates web/ and refuses to touch an existing one.
set -euo pipefail

CONTRACT="${1:?Usage: new-web-app.sh <Contract> [\"Page title\"]}"
TITLE="${2:-$CONTRACT}"
TEMPLATE="$(cd "$(dirname "$0")/../template" && pwd)"

[ -f Odra.toml ] || { echo "Error: run this from the Odra project root (no Odra.toml here)." >&2; exit 1; }
[ ! -e web ] || { echo "Error: web/ already exists." >&2; exit 1; }
grep -q "::$CONTRACT\"" Odra.toml || { echo "Error: no contract named $CONTRACT in Odra.toml." >&2; exit 1; }
case "$TITLE" in *[\&/\|\<\>]*) echo "Error: the title must not contain & / | < >" >&2; exit 1 ;; esac

# The client crate `cargo odra generate-client` creates is named after the project crate.
PROJECT=$(cargo metadata --no-deps --format-version 1 2>/dev/null \
  | sed -n 's/.*"name":"\([^"]*\)_cli".*/\1/p' | head -1)
[ -n "$PROJECT" ] || { echo "Error: cannot find the <project>_cli binary in Cargo.toml." >&2; exit 1; }

cp -r "$TEMPLATE" web
find web -type f \( -name '*.json' -o -name '*.ts' -o -name '*.html' \) -print0 \
  | xargs -0 sed -i.bak -e "s/__CONTRACT__/$CONTRACT/g" -e "s/__PROJECT__/$PROJECT/g" -e "s|__TITLE__|$TITLE|g"
find web -name '*.bak' -delete
echo "Created web/ for $CONTRACT (client package: ${PROJECT}_client/pkg-web)." >&2
