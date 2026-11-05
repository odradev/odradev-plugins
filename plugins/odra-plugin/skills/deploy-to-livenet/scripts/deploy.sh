#!/usr/bin/env bash
# Run the project's Odra CLI binary against a Casper network.
# Usage: deploy.sh <nctl|testnet|mainnet> [cli command and args...]
#   With no command, runs `deploy`. Examples:
#     deploy.sh nctl
#     deploy.sh testnet status
#     deploy.sh nctl upgrade Flipper --gas 400cspr
# Configuration: <network>.env, selected through ODRA_CASPER_LIVENET_ENV (the livenet backend
# loads it, then .env for anything missing). A legacy .env.<network> file is sourced instead
# when <network>.env does not exist.
# Prints a structured summary (key events, errors, verdict) to stderr.

set -euo pipefail

NETWORK="${1:?Usage: deploy.sh <nctl|testnet|mainnet> [cli command and args...]}"
shift
if [ "$#" -eq 0 ]; then
  set -- deploy
fi
COMMAND="$1"

case "$NETWORK" in
  nctl)
    # Verify NCTL Docker container is running
    if ! docker ps --filter name=mynctl --format '{{.Names}}' | grep -q mynctl; then
      echo "Error: NCTL container is not running. Start it first with /odra-plugin:setup-nctl." >&2
      exit 1
    fi
    ;;
  testnet|mainnet)
    ;;
  *)
    echo "Unknown network: $NETWORK (expected nctl, testnet, or mainnet)" >&2
    exit 1
    ;;
esac

# --- Project root: the nearest directory with Odra.toml ---
PROJECT_ROOT="$PWD"
while [ ! -f "$PROJECT_ROOT/Odra.toml" ]; do
  if [ "$PROJECT_ROOT" = "/" ]; then
    echo "Error: no Odra.toml found in $PWD or any parent directory." >&2
    exit 1
  fi
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
cd "$PROJECT_ROOT"

# --- Configuration file ---
if [ -f "$NETWORK.env" ]; then
  echo "Using $NETWORK.env (ODRA_CASPER_LIVENET_ENV=$NETWORK)..." >&2
  export ODRA_CASPER_LIVENET_ENV="$NETWORK"
elif [ -f ".env.$NETWORK" ]; then
  echo "Using legacy .env.$NETWORK (consider renaming it to $NETWORK.env)..." >&2
  set -a && source ".env.$NETWORK" && set +a
else
  echo "Error: neither $NETWORK.env nor .env.$NETWORK found. Set up the environment before deploying." >&2
  exit 1
fi

# --- Wasm files (needed by deploy and upgrade) ---
case "$COMMAND" in
  deploy|upgrade|upgrade-children)
    if [ -z "$(ls -A wasm 2>/dev/null)" ]; then
      echo "Error: no wasm files in $PROJECT_ROOT/wasm. Run 'cargo odra build' first." >&2
      exit 1
    fi
    ;;
esac

# --- CLI binary: the [[bin]] target built from cli.rs ---
CLI_BIN=$(cargo metadata --no-deps --format-version 1 2>/dev/null \
  | jq -r '[.packages[].targets[] | select(.kind | index("bin")) | select(.src_path | endswith("/cli.rs")) | .name] | first // empty')
if [ -z "$CLI_BIN" ]; then
  echo "Error: no [[bin]] target built from cli.rs found. Generated projects name it <project>_cli." >&2
  exit 1
fi

echo "Running '$CLI_BIN $*' on $NETWORK..." >&2
OUTPUT=$(cargo run --bin "$CLI_BIN" -- "$@" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

echo "$OUTPUT"

# --- Summary ---
echo "" >&2
echo "### Summary" >&2
echo "**Network**: $NETWORK   **Command**: $*   **Exit code**: $EXIT_CODE" >&2

echo "" >&2
echo "#### Key Events" >&2
echo "$OUTPUT" | grep -iE 'Deploying|Deploy hash|Contract|package hash|upgraded|Success|Done' >&2 || echo "None" >&2

echo "" >&2
echo "#### Errors" >&2
echo "$OUTPUT" | grep -iE 'panicked|assertion failed|error\[|Error|OutOfGas|VmError' >&2 || echo "None" >&2

echo "" >&2
echo "#### Verdict" >&2
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "'$*' finished successfully on $NETWORK." >&2
else
  echo "'$*' on $NETWORK failed with exit code $EXIT_CODE." >&2
fi

exit "$EXIT_CODE"
