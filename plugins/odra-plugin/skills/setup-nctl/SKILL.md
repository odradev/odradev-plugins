---
name: setup-nctl
description: >
  Extract keys from a running NCTL node and create the .env.nctl file.
  Use when the user says "setup nctl", "configure nctl", "setup-nctl",
  or "create nctl env".
allowed-tools: Bash(docker *)
---

# Setup Local Casper Node (NCTL)

Extracts keys from a running NCTL container and creates the `.env.nctl` configuration file.


## Step 1 — Check Docker

```bash
docker --version
```

If Docker is not installed or not running, tell the user and stop.

---

## Step 2 — Check if NCTL is Already Running

```bash
docker ps --filter name=mynctl --format '{{.Names}}'
```

If `mynctl` is listed, tell the user NCTL is already running and stop and move to step 4.

---

## Step 3 — Start NCTL

```bash
docker run --rm -it --cpus=1 --name mynctl -d \
  -p 11101:11101 \
  -p 14101:14101 \
  -p 18101:18101 \
  -p 25101:25101 \
  makesoftware/casper-nctl:v203
```

Wait for readiness running the bundled wait script under `scripts/wait-for-nctl.sh` with a timeout of 120 seconds
passed as an argument.

```bash
./${CLAUDE_SKILL_DIR}/scripts/wait-for-nctl.sh 120
```

If the wait script exits non-zero, report failure and stop.

---

## Step 4 — Extract Keys

Run the bundled key extraction script under `scripts/extract-keys.sh`:

```bash
./${CLAUDE_SKILL_DIR}/scripts/extract-keys.sh
```

If the script exits non-zero, report error and stop.

---

## Step 5 — Create .env

Create `.env.nctl` from `.env.sample` with nctl defaults:

```env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=.node-keys/secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=http://localhost:11101
ODRA_CASPER_LIVENET_EVENTS_URL=http://localhost:18101/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-net-1
```

---

## Step 6 — Report

```
NCTL environment configured.
- RPC: http://localhost:11101
- Events: http://localhost:18101/events
- Chain: casper-net-1
- Keys: .node-keys/secret_key.pem, .node-keys/secret_key_1.pem
- .env: configured for nctl

To stop: docker stop mynctl
```

### Port Reference

| Port  | Service         |
|-------|-----------------|
| 11101 | JSON-RPC        |
| 14101 | REST API        |
| 18101 | SSE (events)    |
| 25101 | Speculative RPC |

## Edge Cases

- **Docker not running**: If `docker run` fails with a connection error, tell the user Docker Desktop may not be running.
- **Port conflicts**: If ports are already bound, suggest stopping any ewqxisting `mynctl` container first.
- **Key already exists**: Overwrite silently (or warn the user if they seem cautious about overwriting).
- **Custom user**: The default key is for `user-1`. If the user wants a different user (user-2, user-3, etc.), substitute in the path: `/home/casper/casper-nctl/assets/net-1/users/user-N/secret_key.pem`.