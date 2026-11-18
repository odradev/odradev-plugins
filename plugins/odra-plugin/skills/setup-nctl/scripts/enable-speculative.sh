#!/bin/bash
# Turn on what a web app needs from the local NCTL node, which is off by default:
#   - the speculative execution RPC (port 25101), used by the generated wasm client to read
#     contract state;
#   - cross-origin requests to both RPC servers, so a page served from another port may call them.
# Changes the configuration of node 1 inside the `mynctl` container and restarts that node.
# Run it once after the container starts; a new container starts with the defaults again.
set -euo pipefail

docker exec mynctl /bin/bash -c '
set -e
D=$(ls -d /home/casper/casper-nctl/assets/net-1/nodes/node-1/config/*/ | tail -1)
S=/home/casper/casper-nctl/assets/net-1/daemon/config/supervisord.conf
if grep -q "^\[rpc_server.speculative_exec_server\]" "$D/sidecar.toml"; then
  echo "Speculative execution is already enabled." >&2
  exit 0
fi
sed -i "s/allow_request_speculative_exec = false/allow_request_speculative_exec = true/" "$D/config.toml"
sed -i "s/^cors_origin = \"\"/cors_origin = \"*\"/" "$D/sidecar.toml"
cat >> "$D/sidecar.toml" <<TOML

[rpc_server.speculative_exec_server]
enable_server = true
ip_address = "0.0.0.0"
port = 25101
qps_limit = 100
max_body_bytes = 4000000
cors_origin = "*"
default_limit_requests = 100
default_limit_period = "1s"
TOML
supervisorctl -c "$S" restart validators-1:casper-net-1-node-1 validators-1:casper-net-1-sidecar-1 >/dev/null
'

for _ in $(seq 1 40); do
  if curl -s -m 2 http://localhost:25101/rpc -H 'content-type: application/json' \
      --data-raw '{"jsonrpc":"2.0","id":1,"method":"speculative_exec","params":{}}' 2>/dev/null \
      | grep -q "Invalid params" \
    && curl -s -m 2 http://localhost:11101/rpc -H 'content-type: application/json' \
      --data-raw '{"jsonrpc":"2.0","id":1,"method":"info_get_status"}' 2>/dev/null \
      | grep -q '"height":[0-9]'; then
    echo "Speculative execution RPC is ready at http://localhost:25101/rpc." >&2
    exit 0
  fi
  sleep 3
done
echo "Error: the speculative execution RPC did not come up. Check: docker exec mynctl tail /home/casper/casper-nctl/assets/net-1/nodes/node-1/logs/sidecar-stderr.log" >&2
exit 1
