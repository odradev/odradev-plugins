---
name: setup-nctl
description: >
  Extract keys from a running NCTL node and create the nctl.env file.
  Use when the user says "setup nctl", "configure nctl", "setup-nctl",
  or "create nctl env".
allowed-tools: Bash(docker *),Bash(${CLAUDE_SKILL_DIR}/scripts/*),Bash(cat *),Bash(ls *),Bash(grep *),Read,Write,Edit,WebFetch
---

# Setup Local Casper Node (NCTL)

Starts a local Casper network in Docker if needed, extracts the funded keys from the container and
writes the `nctl.env` configuration file the project's CLI binary reads.

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

If `mynctl` is listed, tell the user NCTL is already running and move to step 4.

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

This is the same image and port set the generated project's `.env.sample` documents.

Wait for readiness with the bundled wait script, passing a timeout of 120 seconds:

```bash
${CLAUDE_SKILL_DIR}/scripts/wait-for-nctl.sh 120
```

If the wait script exits non-zero, report failure and stop.

---

## Step 4 — Extract Keys

Run the bundled key extraction script:

```bash
${CLAUDE_SKILL_DIR}/scripts/extract-keys.sh
```

It writes `.node-keys/secret_key.pem` (user-1) and `.node-keys/secret_key_1.pem` (user-2) at the
project root. If the script exits non-zero, report the error and stop.

---

## Step 5 — Create `nctl.env`

Write `nctl.env` at the project root:

```env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=.node-keys/secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=http://localhost:11101
ODRA_CASPER_LIVENET_EVENTS_URL=http://localhost:18101/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-net-1
# second funded account, available as env.get_account(1)
ODRA_CASPER_LIVENET_KEY_1=.node-keys/secret_key_1.pem
```

Why this name: the livenet backend loads `<name>.env` when `ODRA_CASPER_LIVENET_ENV=<name>` is
set, then `.env` for anything still missing. `nctl.env` therefore works with the plugin's deploy
script *and* by hand (`ODRA_CASPER_LIVENET_ENV=nctl cargo run --bin <project>_cli -- whoami`), and
it matches the `*.env` pattern the 2.10 project templates git-ignore. If the project has
`.env.sample` (2.10 templates), its values are already the NCTL ones above except the key path.

If a `.env.nctl` from an earlier version of this plugin exists, leave it — the deploy script still
falls back to it — but write `nctl.env` anyway and tell the user the new name.

---

## Step 6 — Keep secrets out of git

```bash
cat .gitignore
```

Projects generated from the Odra 2.10 templates already ignore `.env`, `*.env` and
`secret_key*.pem` (which also matches the files in `.node-keys/`). For an older project, add to
`.gitignore` whatever is missing:

```gitignore
*.env
.env
.node-keys/
```

---

## Step 7 — Report

```
NCTL environment configured.
- RPC: http://localhost:11101
- Events: http://localhost:18101/events
- Chain: casper-net-1
- Keys: .node-keys/secret_key.pem (account 0), .node-keys/secret_key_1.pem (account 1)
- Config: nctl.env — select it with ODRA_CASPER_LIVENET_ENV=nctl

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
- **Port conflicts**: If ports are already bound, suggest stopping any existing `mynctl` container first.
- **Key already exists**: Overwrite silently (or warn the user if they seem cautious about overwriting).
- **Custom user**: The default key is for `user-1`. If the user wants a different user (user-2, user-3, etc.), substitute in the path: `/home/casper/casper-nctl/assets/net-1/users/user-N/secret_key.pem`.
- **Not a git repository**: `extract-keys.sh` locates the project root with `git rev-parse`; outside
  a repository run it from the project root, or tell the user to `git init` first.

## Reference

- [Livenet backend](https://odra.dev/docs/backends/livenet) — the env vars written to `nctl.env`,
  `ODRA_CASPER_LIVENET_ENV`, and how the backend consumes them
- [`docs-map.md`](../../reference/docs-map.md) — index of the whole documentation set
