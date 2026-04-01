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

## Step 1 — Extract Keys

Run the bundled key extraction script under `scripts/extract-keys.sh`:

```bash
./${CLAUDE_SKILL_DIR}/scripts/extract-keys.sh
```

If the script exits non-zero, report error and stop.

---

## Step 2 — Create .env

Create `.env.nctl` from `.env.sample` with nctl defaults:

```env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=.node-keys/secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=http://localhost:11101
ODRA_CASPER_LIVENET_EVENTS_URL=http://localhost:18101/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-net-1
```

---

## Step 3 — Report

```
NCTL environment configured.
- RPC: http://localhost:11101
- Events: http://localhost:18101/events
- Chain: casper-net-1
- Keys: .node-keys/secret_key.pem, .node-keys/secret_key_1.pem
- .env: configured for nctl

To stop: docker stop mynctl
```
