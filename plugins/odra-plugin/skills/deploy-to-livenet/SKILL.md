---
name: deploy-to-livenet
description: >
  Deploy or upgrade contracts on a Casper network (nctl, testnet, or mainnet).
  Use when the user says "deploy", "deploy to livenet", "deploy to nctl",
  "deploy to testnet", "deploy to mainnet", "run on livenet", "upgrade on livenet",
  or "deploy-to-livenet".
allowed-tools: Bash(docker ps *),Bash(cargo *),Bash(${CLAUDE_SKILL_DIR}/scripts/*),Bash(ls *),Bash(cat *),Skill(setup-nctl),Skill(setup-account),Read,Write,AskUserQuestion,WebFetch
---

# Deploy Contracts to Livenet

Deploys contracts using the project's CLI binary (`bin/cli.rs`, built as `<project>_cli`) against
a Casper network. The same binary upgrades deployed contracts.

---

## Step 1 — Identify Target Network

If not stated, ask the user with `AskUserQuestion`:
- **nctl** — local Docker node
- **testnet** — Casper test network
- **mainnet** — Casper main network

---

## Step 2 — Ensure Environment is Ready

The CLI reads its configuration from `<network>.env` (`nctl.env`, `testnet.env`, `mainnet.env`),
selected with `ODRA_CASPER_LIVENET_ENV=<network>`; `.env` fills in anything missing. The 2.10
project templates git-ignore `*.env` and `secret_key*.pem`; for an older project, check
`.gitignore` before writing a file that names a key.

### For nctl

Run `/odra-plugin:setup-nctl`. It starts the node if needed and writes `nctl.env`.

### For testnet

If `testnet.env` does not exist, run `/odra-plugin:setup-account`: it creates or takes a key, gets
the account funded (the faucet) and writes the file:

```env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=keys/testnet_secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=https://node.testnet.casper.network
ODRA_CASPER_LIVENET_EVENTS_URL=https://node.testnet.casper.network/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-test
```

`https://node.testnet.casper.network` is the public node of the Casper Association and needs no
registration. Alternatives:

- **CSPR.cloud**: `https://node.testnet.cspr.cloud` (events: `.../events`) — **only with**
  `CSPR_CLOUD_AUTH_TOKEN=<token>` in the file (free at <https://console.cspr.build>). Without a
  token it answers `401 authorization is not provided`.
- **A peer of the network**: the bundled discovery script fetches peers, tests connectivity and
  prints a responsive node IP; the addresses are then `http://<node-ip>:7777` and
  `http://<node-ip>:9999/events`:
  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/discover-node.sh testnet
  ```

An account that has never received CSPR does not exist on chain: every command then fails with
`Couldn't get purse uref for address`. Fund it first.

### For mainnet

Same flow (`/odra-plugin:setup-account` for mainnet, or `/odra-plugin:go-mainnet` for the whole
launch) but:
- Public node: `https://node.mainnet.casper.network` (events:
  `https://node.mainnet.casper.network/events`); or `https://node.cspr.cloud` with a token, or
  `${CLAUDE_SKILL_DIR}/scripts/discover-node.sh mainnet`
- Chain name: `casper`
- Write to `mainnet.env`

Confirm with the user before any mainnet transaction — it costs real CSPR.

---

## Step 3 — Check how the deploy script installs the contracts

Before the first deployment to a network the user cares about (testnet, mainnet), read the deploy
script in `bin/cli.rs` (`cli/cli.rs` in a workspace). The project template deploys with
`load_or_deploy`, which installs a **locked** package: it can never be upgraded, only redeployed
under a new address. If the contracts may need an upgrade later, have `smart-contract-writer`
switch the script to `load_or_deploy_with_cfg(.., InstallConfig::upgradable::<Contract>(), ..)`
before deploying, and say so to the user either way. On nctl it does not matter — redeploying is free.

## Step 4 — Build the wasm

The CLI deploys `wasm/<Contract>.wasm`. Build (or rebuild after source changes) first:

```bash
cargo odra build
```

In a workspace the `wasm/` directory is at the workspace root. The deploy script refuses to run
without it.

---

## Step 5 — Run Deployment

Run the bundled deploy script:

```bash
${CLAUDE_SKILL_DIR}/scripts/deploy.sh <nctl|testnet|mainnet>
```

The script finds the CLI binary from `cargo metadata` (the `[[bin]]` target built from `cli.rs`),
selects `<network>.env` through `ODRA_CASPER_LIVENET_ENV` (falling back to a legacy
`.env.<network>` file), runs the `deploy` command and prints a structured summary (key events,
errors, verdict) to stderr.

Anything after the network name is passed to the CLI instead of `deploy`, so the same script runs
every other command against that network:

```bash
${CLAUDE_SKILL_DIR}/scripts/deploy.sh nctl status
${CLAUDE_SKILL_DIR}/scripts/deploy.sh nctl contract Flipper get
${CLAUDE_SKILL_DIR}/scripts/deploy.sh nctl scenario flip --number 3
```

Environment variables of the calling shell reach the deploy script, so a script that reads its
constructor arguments with `std::env::var` is parameterised on the command line (record the values
used — nothing else does):

```bash
ROUND_DURATION_MS=300000 ${CLAUDE_SKILL_DIR}/scripts/deploy.sh testnet
```

What a transaction cost — the CLI prints its hash and explorer link, not the cost:

```bash
${CLAUDE_SKILL_DIR}/scripts/tx-cost.sh testnet <transaction hash or explorer link>
# limit 450.000 CSPR, consumed 386.902 CSPR, refund 47.323 CSPR, charged 402.677 CSPR
```

The charge is the consumed gas plus a quarter of the unused part of the limit. Before the first
install on a network where CSPR matters, measure the consumption on the Casper VM (a test printing
`env.gas_report()`, run with `ODRA_BACKEND=casper cargo test <name> -- --nocapture`) and set the
limit in the deploy script to that plus 15–20%; the template's default limit is a guess.

**Important:**
- Deployments can take 30-90 seconds per contract
- Use a generous timeout (10 minutes)
- `deploy` is idempotent when the deploy script uses `load_or_deploy`: deployed addresses are kept
  in `resources/<chain>-contracts.toml` and reused on the next run

---

## Step 6 — Upgrading an already deployed contract

Since Odra 2.10 the CLI upgrades a contract from the contracts file without a custom scenario. The
contract must have been **installed upgradable**: `load_or_deploy_with_cfg` /
`try_deploy_with_cfg` with `InstallConfig::upgradable::<T>()`. A plain `load_or_deploy` or
`try_deploy` installs a locked package, and the upgrade fails with
`A locked contract cannot be upgraded` — then only a redeploy under a new address is possible; tell
the user before spending gas. Run the upgrade as the account that installed the contract. After
`cargo odra build` with the new code:

```bash
${CLAUDE_SKILL_DIR}/scripts/deploy.sh <network> upgrade <Contract> --gas 400cspr [--<upgrade arg> <value>...]
# e.g. `upgrade(&mut self, registry: Address)`:
${CLAUDE_SKILL_DIR}/scripts/deploy.sh nctl upgrade Counter --registry hash-0878bb…9300f21 --gas 400cspr
```

The arguments are those of the contract's `upgrade` entry point, as flat flags (`upgrade <Contract> --help`
lists them). A package hash another contract needs comes from `status` or the contracts file. `--force-create-upgrade-group`,
`--allow-key-override` and `--package-named-key` set the `UpgradeConfig` (see
`upgrade <Contract> --help`). The package hash does not change, so the contracts file stays as it is.

The children of a factory run the factory's code: upgrade the factory, then all of its children in
one transaction (or `--batch-size N` children per transaction):

```bash
${CLAUDE_SKILL_DIR}/scripts/deploy.sh <network> upgrade <Factory> --gas 500cspr
${CLAUDE_SKILL_DIR}/scripts/deploy.sh <network> upgrade-children <Factory> --gas 900cspr [--<upgrade arg> <value>...]
```

---

## Step 7 - Summary and Reporting

Do not truncate the output. If the deploy was successful, report success and the relevant hashes
(and where they were saved: `resources/<chain>-contracts.toml`). If there were errors, report
failure and include the error messages. On livenet a reverted `init` or `upgrade` comes back as the
contract's own error (named from the schema in `resources/casper_contract_schemas/`); keep the
schemas current with `cargo odra schema` so errors are named rather than numbered.

---

## Step 8 - Cleanup

Clean up is applicable if the user deployed to nctl.

Ask the user if they want to remove the NCTL container. If yes:
1. Stop the container: `docker stop mynctl`
2. Remove keys: `rm -rf .node-keys`
3. Remove the related `resources/casper-net-1-contracts.toml` if it exists.

---

## Reference

- [Livenet backend](https://odra.dev/docs/backends/livenet) — env vars, deploy flow, gas handling,
  rate limits, how errors are decoded, `ODRA_CASPER_LIVENET_STATE_ROOT_HASH`
- [Odra CLI](https://odra.dev/docs/tutorials/odra-cli) — the `bin/cli.rs` scenarios this skill runs,
  and every built-in command (`deploy`, `contract`, `scenario`, `upgrade`, `upgrade-children`,
  `status`, `inspect`, `storage`, `print-events`, `transfer`, `whoami`, `config`, `repl`)
- [Deploying a Token on Casper Livenet](https://odra.dev/docs/tutorials/deploying-on-casper) — a
  complete worked deployment
- [Upgrading Contracts](https://odra.dev/docs/tutorials/upgrades) — what an upgrade does to entry
  points and storage
- [`docs-map.md`](../../reference/docs-map.md) — index of the whole documentation set
