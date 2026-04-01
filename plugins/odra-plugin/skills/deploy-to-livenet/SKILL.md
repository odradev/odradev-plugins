---
name: deploy-to-livenet
description: >
  Deploy contracts to a Casper network (nctl, testnet, or mainnet).
  Use when the user says "deploy", "deploy to livenet", "deploy to nctl",
  "deploy to testnet", "deploy to mainnet", "run on livenet", or "deploy-to-livenet".
allowed-tools: Bash(docker ps *),Bash(cargo *),Skill(setup-nctl),Skill(start-nctl)
---

# Deploy Contracts to Livenet

Deploys contracts using the CLI binary against a Casper network.

---

## Step 1 — Identify Target Network

If not stated, ask the user:
- **nctl** — local Docker node
- **testnet** — Casper test network
- **mainnet** — Casper main network

User AskUserQuestion tool.

---

## Step 2 — Ensure Environment is Ready

### For nctl

Check if NCTL is running the bundled script under `scripts/check-nctl.sh`.

```bash
./${CLAUDE_SKILL_DIR}/scripts/check-nctl.sh
```

If not running, run `/start-nctl` and then `/setup-nctl` to extract keys and create the `.env.nctl` file.
If already running, ensure `.env.nctl` exists. If not, run `/setup-nctl`.

### For testnet

Check if `.env.testnet` exists. If not, create it:

1. Ask if the user wants to provide a node address manually. If so, skip to step 3.

2. Discover a responsive node using the bundled script under `scripts/discover-node.sh` with `testnet` as an argument.
   The script fetches peers, tests connectivity, and prints the responsive node IP to stdout.

```bash
./${CLAUDE_SKILL_DIR}/scripts/discover-node.sh testnet
```

3. Ask the user for their secret key path (must be a `.pem` file on disk). Verify it exists.

4. Write `.env.testnet`:
   ```env
   ODRA_CASPER_LIVENET_SECRET_KEY_PATH=<user-provided-path>
   ODRA_CASPER_LIVENET_NODE_ADDRESS=http://<responsive-node-ip>:7777
   ODRA_CASPER_LIVENET_EVENTS_URL=http://<responsive-node-ip>:9999/events
   ODRA_CASPER_LIVENET_CHAIN_NAME=casper-test
   ```

### For mainnet

Same flow as testnet but:
- Run `./${CLAUDE_SKILL_DIR}/scripts/discover-node.sh mainnet` for node discovery
- Chain name: `casper`
- Write to `.env.mainnet`

---

## Step 3 — Run Deployment

Run the bundled deploy script:

```bash
./${CLAUDE_SKILL_DIR}/scripts/deploy.sh <nctl|testnet|mainnet>
```

---

## Step 4 - Summary and Reporting

Do not truncate the output. If the deploy was successful, report success and the relevant hashes. If there were errors, report failure and include the error messages.

**Important:**
- Deployments can take 30-90 seconds per contract
- Use a generous timeout (10 minutes)
- The script loads the `.env.<network>` file, runs the deploy, and prints a structured summary (key events, errors, verdict) to stderr


---

## Step 5 - Cleanup

Clean up is applicable if the user deployed to nctl.

Ask the user if they want to remove the NCTL container. If yes:
1. Stop the container: `docker stop mynctl`
2. Remove keys: `rm -rf .node-keys`
3. Remove a related `*-contracts.toml` under `resources/` if it exists.