---
name: start-nctl
description: >
  Start a local Casper NCTL node using Docker, wait for readiness, and extract keys.
  Use when the user says "start nctl", "start node", "start local node",
  "run nctl", or "start-nctl".
allowed-tools: Bash(docker *)
---

# Start Local Casper Node (NCTL)

Starts a local Casper blockchain node via Docker for testing contract deployments.

---

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

If `mynctl` is listed, tell the user NCTL is already running and stop.

---

## Step 3 — Start NCTL

```bash
docker run --rm -it --cpus=1 --name mynctl -d -p 11101:11101 -p 18101:18101 makesoftware/casper-nctl:v203
```

Wait for readiness running the bundled wait script under `scripts/wait-for-nctl.sh` with a timeout of 120 seconds
passed as an argument.

```bash
./${CLAUDE_SKILL_DIR}/scripts/wait-for-nctl.sh 120
```

If the wait script exits non-zero, report failure and stop.

---

## Step 4 — Report

```
NCTL node is running.
- RPC: http://localhost:11101
- Events: http://localhost:18101/events

Run /setup-nctl to extract keys and create the .env.nctl file.
To stop: docker stop mynctl
```
