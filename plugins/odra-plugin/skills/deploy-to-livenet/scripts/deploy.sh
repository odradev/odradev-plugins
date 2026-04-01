#!/usr/bin/env bash
# Deploy contracts to a Casper network.
# Usage: deploy.sh <nctl|testnet|mainnet>
# Loads the matching .env file, runs `cargo run --bin cli deploy`,
# and prints a structured deployment summary.

set -euo pipefail

NETWORK="${1:?Usage: deploy.sh <nctl|testnet|mainnet>}"

case "$NETWORK" in
  nctl)
    ENV_FILE=".env.nctl"
    # Verify NCTL Docker container is running
    if ! docker ps --filter name=mynctl --format '{{.Names}}' | grep -q mynctl; then
      echo "Error: NCTL container is not running. Start it first with /start-nctl." >&2
      exit 1
    fi
    ;;
  testnet)
    ENV_FILE=".env.testnet"
    ;;
  mainnet)
    ENV_FILE=".env.mainnet"
    ;;
  *)
    echo "Unknown network: $NETWORK (expected nctl, testnet, or mainnet)" >&2
    exit 1
    ;;
esac

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Set up the environment before deploying." >&2
  exit 1
fi

echo "Loading environment from $ENV_FILE..." >&2
set -a && source "$ENV_FILE" && set +a

echo "Deploying contracts to $NETWORK..." >&2
OUTPUT=$(cargo run --bin cli deploy 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

echo "$OUTPUT"

# --- Deployment Summary ---
echo "" >&2
echo "### Deployment Summary" >&2
echo "**Network**: $NETWORK   **Exit code**: $EXIT_CODE" >&2

echo "" >&2
echo "#### Key Events" >&2
echo "$OUTPUT" | grep -iE 'Deploying|Deploy hash|Contract|Success|Done' >&2 || echo "None" >&2

echo "" >&2
echo "#### Errors" >&2
echo "$OUTPUT" | grep -iE 'panicked|assertion failed|error\[|Error' >&2 || echo "None" >&2

echo "" >&2
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "#### Verdict" >&2
  echo "All contracts deployed successfully to $NETWORK." >&2
else
  echo "#### Verdict" >&2
  echo "Deployment to $NETWORK failed with exit code $EXIT_CODE." >&2
fi

exit "$EXIT_CODE"
