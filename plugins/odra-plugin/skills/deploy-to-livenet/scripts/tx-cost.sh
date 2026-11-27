#!/usr/bin/env bash
# Print what a transaction cost: its payment limit, the gas it consumed, the refund and the
# amount actually charged, in CSPR.
# Usage: tx-cost.sh <testnet|mainnet|nctl> <transaction-hash>
# The Odra CLI prints the hash of every transaction it sends (the testnet.cspr.live link).
# charged = limit - refund; the refund is 75% of what the transaction did not consume.
set -euo pipefail

NETWORK="${1:?Usage: tx-cost.sh <testnet|mainnet|nctl> <transaction-hash>}"
HASH="${2:?Usage: tx-cost.sh <testnet|mainnet|nctl> <transaction-hash>}"
case "$NETWORK" in
  testnet) NODE="https://node.testnet.casper.network/rpc" ;;
  mainnet) NODE="https://node.mainnet.casper.network/rpc" ;;
  nctl) NODE="http://localhost:11101/rpc" ;;  # the local node of setup-nctl; fees as on testnet
  *) echo "Unknown network: $NETWORK (expected testnet, mainnet or nctl)" >&2; exit 1 ;;
esac
HASH="${HASH##*/}"   # accept an explorer link too

RESPONSE=$(curl -sS -m 30 -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"info_get_transaction\",\"params\":{\"transaction_hash\":{\"Version1\":\"$HASH\"}}}" \
  "$NODE")
field() { printf '%s' "$RESPONSE" | sed -n "s/.*\"$1\":\"\\([0-9]*\\)\".*/\\1/p"; }
cspr() { awk -v m="$1" 'BEGIN { printf "%.3f", m / 1000000000 }'; }

LIMIT=$(field limit); CONSUMED=$(field consumed); REFUND=$(field refund)
if [ -z "$LIMIT" ] || [ -z "$CONSUMED" ]; then
  echo "Error: no execution result for $HASH on $NETWORK (unknown hash, or not executed yet): $(printf '%s' "$RESPONSE" | cut -c1-200)" >&2
  exit 1
fi
REFUND="${REFUND:-0}"
echo "limit $(cspr "$LIMIT") CSPR, consumed $(cspr "$CONSUMED") CSPR, refund $(cspr "$REFUND") CSPR, charged $(cspr $((LIMIT - REFUND))) CSPR"
if printf '%s' "$RESPONSE" | grep -q '"error_message":"'; then
  echo "failed: $(printf '%s' "$RESPONSE" | sed -n 's/.*"error_message":"\([^"]*\)".*/\1/p')"
fi
