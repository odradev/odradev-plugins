---
name: setup-account
description: >
  Create a Casper account for deploying contracts, get it funded (testnet faucet or real CSPR)
  and write the network configuration file the Odra CLI reads. Use when the user says "create an
  account", "I have no account", "get testnet CSPR", "faucet", "generate a key", "set up testnet",
  "setup-account", or when a deployment needs `testnet.env` / `mainnet.env` and none exists.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/*),Bash(ls *),Bash(cat *),Bash(grep *),Read,Write,Edit,AskUserQuestion,WebFetch
---

# Set up a Casper account

Ends with: a secret key file on disk, an account that holds CSPR, and `<network>.env` in the
project root. `deploy-to-livenet` takes over from there. For a local node use `setup-nctl` instead —
it comes with funded accounts.

Assume the user has never used a blockchain. Say what each step is for; the explanations below are
written to be passed on.

---

## Step 1 — Explain what an account is (skip for a user who knows)

> A Casper account is a key pair. The **secret key** is a small file; whoever has it controls the
> account, and it cannot be recovered or reset. The **public key** (starts with `01` or `02`) is the
> address you can share — it is how others send you CSPR and how explorers show you.
> Every transaction costs a fee in **CSPR**, the network's currency. **Testnet** is a full copy of
> the network where CSPR is free and worthless, made for trying things out; **mainnet** is the real
> one.

## Step 2 — Get a key

Check first: `ls *.env` and the `ODRA_CASPER_LIVENET_SECRET_KEY_PATH` inside `<network>.env`. If the
file exists and its key file exists, skip to Step 3.

Otherwise ask with `AskUserQuestion`:

- **Create a new key (default for a newcomer)**
  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/new-key.sh keys/testnet_secret_key.pem
  ```
  It prints the public key and never overwrites an existing file. Use `keys/mainnet_secret_key.pem`
  for mainnet: **one key per network** — a testnet key gets pasted into chats and scripts, a mainnet
  key holds money.
- **Use a key file the user already has** — take the path, verify it exists, print its public key:
  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/public-key.sh <path>
  ```
- **Use an account from Casper Wallet** — the user downloads the key in the wallet
  (*Menu → Download account keys*) and gives you the path of the `.pem` file.

Rules for key files:

- Keep them out of git. The Odra templates ignore `secret_key*.pem`; a `keys/` directory is **not**
  covered — add `keys/` to `.gitignore` in the same step that creates it, and check with
  `git check-ignore keys/testnet_secret_key.pem`.
- Never print a secret key, never paste it into a chat, a URL or a web form, and never read its
  contents into your reply. The public key is safe to show.
- Tell the user where the file is and that losing it means losing the account. For mainnet, tell
  them to back it up before any CSPR is sent to it.

## Step 3 — Fund the account

Check the balance (exit code 2 means the account has never received anything — an account does not
exist on chain until its first incoming transfer):

```bash
${CLAUDE_SKILL_DIR}/scripts/balance.sh testnet keys/testnet_secret_key.pem
```

### Testnet — the faucet is a step for the human

There is no faucet API. The faucet needs a wallet sign-in, so walk the user through it and wait:

1. Install the **Casper Wallet** browser extension from <https://www.casperwallet.io/download> and
   create a wallet (a password and a 24-word recovery phrase — the phrase restores the wallet's own
   accounts, write it down).
2. In the wallet: *Menu → Import account*, choose the key file from Step 2
   (`keys/testnet_secret_key.pem`). This puts the deployer account in the wallet. The user picks the
   file in their own browser; you do not handle it.
3. Open <https://testnet.cspr.live/tools/faucet>, click **Sign in** (top right), connect the
   imported account, then **Request tokens**.
4. The faucet sends **5,000 test CSPR, once per account**. A second request fails with
   `User error: 1`.

Then poll `balance.sh` until it reports the funds (a transfer takes under a minute).

If the faucet was already used for this account: create another key and use the faucet for it, send
CSPR from any funded testnet account (the minimum transfer is 2.5 CSPR), or ask in the Casper
developer chat (<https://t.me/CSPRDevelopers>).

5,000 CSPR is enough for a handful of deployments: installing a contract costs roughly 1 CSPR per
KB of its wasm file — about 280 CSPR for a CEP-18 token, 365 CSPR for an NFT contract with some
logic (measured on testnet). Calls cost a few CSPR each.

### Mainnet — real money

The user buys CSPR and sends it to the public key from Step 2: the **Buy** button in Casper Wallet
(switched to Mainnet), or an exchange that lists CSPR, then a withdrawal to the public key. You
never do this for them and never ask for exchange or card details. Say how much to send — see the
cost estimate in `go-mainnet` — and have them send a small test amount first.

## Step 4 — Write `<network>.env`

In the project root (the Odra templates git-ignore `*.env`; check `.gitignore` in an older project):

```env
# testnet.env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=keys/testnet_secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=https://node.testnet.casper.network
ODRA_CASPER_LIVENET_EVENTS_URL=https://node.testnet.casper.network/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-test
```

```env
# mainnet.env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=keys/mainnet_secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=https://node.mainnet.casper.network
ODRA_CASPER_LIVENET_EVENTS_URL=https://node.mainnet.casper.network/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper
```

These are the public nodes of the Casper Association and need no registration.
`https://node.testnet.cspr.cloud` / `https://node.cspr.cloud` are an alternative **only with a
token** (`CSPR_CLOUD_AUTH_TOKEN=...`, free at <https://console.cspr.build>); without one they answer
`401 authorization is not provided`.

## Step 5 — Report

Tell the user, in this order: the public key, a link to the account
(`https://testnet.cspr.live/account/<public key>`, `https://cspr.live/account/<public key>` on
mainnet), the balance, where the secret key file is, and what comes next
(`/odra-plugin:deploy-to-livenet`).

---

## Reference

- [Accounts and keys](https://docs.casper.network/concepts/accounts-and-keys) — key formats,
  `casper-client keygen` (an alternative to `new-key.sh` when `casper-client` is installed; it also
  creates secp256k1 keys, public keys starting with `02`)
- [Testnet faucet](https://docs.casper.network/users/testnet-faucet)
- [Casper Wallet user guide](https://www.casperwallet.io/user-guide/getting-started)
- [Livenet backend](https://odra.dev/docs/backends/livenet) — every variable of `<network>.env`
