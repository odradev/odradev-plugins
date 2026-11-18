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

# The client of Odra 2.10 never answers a read of a mapping nobody has written to yet, and takes
# the key only as a one-line PEM. Checked for a crates.io dependency; a git or path one passes.
ODRA_ID="$(cargo pkgid odra 2>/dev/null || true)"
case "$ODRA_ID" in
  registry+*)
    ODRA_VERSION="${ODRA_ID##*[#@]}"
    if [ "$(printf '%s\n' 2.11.0 "$ODRA_VERSION" | sort -V | head -n1)" != "2.11.0" ]; then
      echo "Error: this project uses Odra $ODRA_VERSION; the web client needs 2.11.0 or newer." >&2
      echo "Set the odra crates in Cargo.toml to 2.11.0 (https://odra.dev/docs/migrations/to-2.11.0), run the tests, then run this again." >&2
      exit 1
    fi ;;
esac

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

# The client crate is built on its own; keep its build output out of git.
if [ -f .gitignore ] && ! grep -q "_client/target" .gitignore; then
  printf '\n# generated contract client: build output\n/*_client/target\n/*_client/pkg-web\n' >> .gitignore
fi

WASM_CLIENT_SK="$(cat "$READER_KEY")" cargo odra generate-client

echo "Reader account (public key): $("$ACCOUNT_SCRIPTS/public-key.sh" "$READER_KEY")" >&2
