#!/usr/bin/env bash
# Print the CSPR balance of an account.
# Usage: balance.sh <testnet|mainnet> <public-key-hex | secret-key-path>
# Prints the balance in CSPR to stdout. Exit code 0: funded, 2: the account does not exist on
# chain yet (it has never received CSPR), 1: any other error.
set -euo pipefail

NETWORK="${1:?Usage: balance.sh <testnet|mainnet> <public-key-hex | secret-key-path>}"
WHO="${2:?Usage: balance.sh <testnet|mainnet> <public-key-hex | secret-key-path>}"
case "$NETWORK" in
  testnet) NODE="https://node.testnet.casper.network/rpc" ;;
  mainnet) NODE="https://node.mainnet.casper.network/rpc" ;;
  *) echo "Unknown network: $NETWORK (expected testnet or mainnet)" >&2; exit 1 ;;
esac
if [ -f "$WHO" ]; then
  WHO=$("$(dirname "$0")/public-key.sh" "$WHO")
fi

RESPONSE=$(curl -sS -m 30 -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"query_balance\",\"params\":{\"purse_identifier\":{\"main_purse_under_public_key\":\"$WHO\"}}}" \
  "$NODE")
MOTES=$(printf '%s' "$RESPONSE" | sed -n 's/.*"balance":"\([0-9]*\)".*/\1/p')
if [ -n "$MOTES" ]; then
  # 1 CSPR = 1_000_000_000 motes
  PADDED=$(printf '%010d' "$MOTES" 2>/dev/null || echo "$MOTES")
  echo "${PADDED:0:${#PADDED}-9}.${PADDED: -9} CSPR" | sed 's/^0*\([0-9]\)/\1/'
  exit 0
fi
if printf '%s' "$RESPONSE" | grep -q "Purse not found"; then
  echo "0 CSPR - the account $WHO does not exist on $NETWORK yet (it has never received CSPR)." >&2
  exit 2
fi
echo "Error: unexpected answer from $NODE: $RESPONSE" >&2
exit 1
