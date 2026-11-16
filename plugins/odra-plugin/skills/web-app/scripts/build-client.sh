#!/usr/bin/env bash
# Generate the TypeScript client of the project's contracts (wraps `cargo odra generate-client`).
# Usage: build-client.sh
# Run from the Odra project root, again after every change of an entry point, event or error.
#
# The client reads contract state by simulating calls, and a simulated call must be signed by
# some account. That "reader" key is compiled into the client, so it is public to every visitor:
# it is a dedicated throwaway key (keys/reader_secret_key.pem, created here on first run) and
# must never be the deployer's key or hold more CSPR than the reads need.
set -euo pipefail

[ -f Odra.toml ] || { echo "Error: run this from the Odra project root (no Odra.toml here)." >&2; exit 1; }
command -v wasm-pack >/dev/null || { echo "Error: wasm-pack is not installed. Install it with: cargo install wasm-pack" >&2; exit 1; }

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
ACCOUNT_SCRIPTS="$SCRIPTS/../../setup-account/scripts"
READER_KEY="${READER_KEY:-keys/reader_secret_key.pem}"

if [ ! -f "$READER_KEY" ]; then
  "$ACCOUNT_SCRIPTS/new-key.sh" "$READER_KEY" >/dev/null
  echo "Created the reader key $READER_KEY." >&2
fi
if [ -n "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ] && ! git check-ignore -q "$READER_KEY"; then
  echo "Warning: $READER_KEY is not git-ignored. Add its directory to .gitignore." >&2
fi
for ENV_FILE in *.env; do
  [ -f "$ENV_FILE" ] || continue
  if grep -q "SECRET_KEY_PATH=$READER_KEY\$" "$ENV_FILE"; then
    echo "Error: $READER_KEY is the deployer key of $ENV_FILE. The reader key becomes public; use a separate one." >&2
    exit 1
  fi
done

# The key reaches the build through a cargo directive that ends at the first newline, so it is
# passed as a one-line PEM (which the client parses fine).
WASM_CLIENT_SK="$(tr -d '\r\n' < "$READER_KEY")" cargo odra generate-client

echo "Reader account (public key): $("$ACCOUNT_SCRIPTS/public-key.sh" "$READER_KEY")" >&2
