#!/usr/bin/env bash
# Discover a responsive Casper node for a given network.
# Usage: discover-node.sh <testnet|mainnet>
# Outputs the responsive node IP on success, exits 1 on failure.

set -euo pipefail

NETWORK="${1:?Usage: discover-node.sh <testnet|mainnet>}"

case "$NETWORK" in
  testnet)
    DISCOVERY_URL="https://node.testnet.cspr.cloud/rpc"
    REFERER="https://testnet.cspr.live/"
    ;;
  mainnet)
    DISCOVERY_URL="https://node.cspr.cloud/rpc"
    REFERER="https://cspr.live/"
    ;;
  *)
    echo "Unknown network: $NETWORK (expected testnet or mainnet)" >&2
    exit 1
    ;;
esac

echo "Fetching peers from $NETWORK..." >&2

PEERS=$(curl -s "$DISCOVERY_URL" \
  -H 'content-type: application/json' \
  -H "referer: $REFERER" \
  --data-raw '{"jsonrpc":"2.0","id":"1","method":"info_get_peers"}' \
  | jq -r '.result.peers[:50][] | .address' 2>/dev/null)

if [ -z "$PEERS" ]; then
  echo "No peers found." >&2
  exit 1
fi

PEER_COUNT=$(echo "$PEERS" | wc -l | tr -d ' ')
echo "Found $PEER_COUNT peers, testing connectivity..." >&2

for PEER in $PEERS; do
  NODE_IP="${PEER%%:*}"
  echo "  Testing $NODE_IP..." >&2
  RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 \
    "http://$NODE_IP:7777/rpc" \
    -H 'content-type: application/json' \
    --data-raw '{"jsonrpc":"2.0","id":"1","method":"rpc.discover"}' 2>/dev/null || true)

  if [ -n "$RESPONSE" ] && echo "$RESPONSE" | jq -e '.result' >/dev/null 2>&1; then
    echo "Found responsive node: $NODE_IP" >&2
    echo "$NODE_IP"
    exit 0
  fi
done

echo "No responsive node found." >&2
exit 1
