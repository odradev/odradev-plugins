---
name: go-mainnet
description: >
  Take a project that works on Casper testnet to mainnet: readiness review, cost estimate, a
  mainnet account funded with real CSPR, deployment, the production web app and the listing of its
  tokens. Use when the user says "go to mainnet", "go live", "launch", "production", "release it
  for real", "how much will mainnet cost", or "go-mainnet".
allowed-tools: Skill, Bash(${CLAUDE_SKILL_DIR}/../setup-account/scripts/*),Bash(${CLAUDE_SKILL_DIR}/../deploy-to-livenet/scripts/*),Bash(${CLAUDE_SKILL_DIR}/../web-app/scripts/*),Bash(cargo odra *),Bash(npm *),Bash(git *),Bash(ls *),Bash(cat *),Bash(grep *),Read,Write,Edit,AskUserQuestion,WebFetch
---

# Going to mainnet

Mainnet is the same software as testnet with one difference: the CSPR is real, and so is everything
users do. Nothing here can be undone. Work through the steps in order, **stop for the user's
explicit yes before every mainnet transaction**, and state the cost before asking.

The flow never needs the user's testnet habits to be unsafe: a **new key** for mainnet, the same
code that was tested, the same commands with `mainnet` in place of `testnet`.

---

## Step 1 — Is it ready? (you check, then report)

Do not ask the user to assert these; verify each and report a pass or a finding.

- [ ] **The code is the tested code.** `git status` is clean; `cargo odra test` and
  `cargo odra test -b casper` pass on this commit.
- [ ] **It ran on testnet end to end**, including the web app, with this exact code
  (`resources/casper-test-contracts.toml` exists; if the contracts changed since that deploy,
  redeploy or upgrade on testnet first).
- [ ] **Every CSPR that goes in can come out.** Re-read each payable entry point: is there a path
  that leaves funds in the contract forever (a round nobody settles, a refund to an address that
  cannot receive)? A test should assert the contract balance returns to zero.
- [ ] **Access control.** List every entry point that changes state and who may call it. No
  unguarded mint, burn, withdraw or configuration setter. Say the list to the user.
- [ ] **Arithmetic.** Subtractions and divisions on user-supplied amounts are guarded (Odra does
  not add checked arithmetic).
- [ ] **Constructor arguments are the production ones**: real durations (not the 10-minute testnet
  rounds), real prices, the right owner. Print the values the deploy script will use.
- [ ] **Upgradability is a decision the user made.** Upgradable: bugs can be fixed, and users must
  trust the deployer key. Locked: nobody can change it, ever.
- [ ] **Secrets are out of git**: `git ls-files | grep -E '\.pem$|\.env$'` prints nothing.

Then say plainly what a review by you does and does not mean: you looked for the common mistakes;
this is not a security audit. For a contract that will hold significant value of other people,
recommend an independent audit before launch, and a launch with low limits.

## Step 2 — What it will cost

Fees on mainnet and testnet are priced identically (1 mote per unit of gas on both), so **testnet
measurements are the estimate**. Collect them:

- what each install consumed on testnet:
  `${CLAUDE_SKILL_DIR}/../deploy-to-livenet/scripts/tx-cost.sh testnet <hash>` (the hashes are in
  the deploy output and on the contract package page of `testnet.cspr.live`);
- the same for one call of each user action (this is what *users* will pay per action).

How the fee works: a transaction states a payment limit; **75% of the unused part is refunded**
and the rest is burned. So a generous limit costs something: with a 500 CSPR limit and 200 CSPR
consumed, the charge is 200 + 25% × 300 = 275 CSPR. For mainnet, set each limit in the deploy
script to the measured consumption plus about 20%, not to a round big number. One install can
spend at most 1,000 CSPR and a wasm file may be at most 750 KB. For orientation (testnet, 2026-11):
a 318 KB CEP-18 token consumed about 280 CSPR, a 378 KB NFT auction about 365 CSPR, a payable call
6–7 CSPR, opening a CSPR.trade pool about 410 CSPR.

Tell the user a total: installs + a reserve for a failed attempt + a few CSPR for the web app's
reader account + (if a token is listed) the CSPR side of the liquidity pool, which is their money
placed in the pool, not a fee. Give the CSPR figure; for the price in their currency point them to
<https://cspr.live> (the rate is on the front page) — do not quote a rate from memory.

## Step 3 — A mainnet account

`/odra-plugin:setup-account` for **mainnet**: a new key (`keys/mainnet_secret_key.pem`), never the
testnet one. Before any CSPR is sent to it:

- the user backs up the key file somewhere off this machine;
- `git check-ignore keys/mainnet_secret_key.pem` succeeds.

The user buys CSPR (the Buy button of Casper Wallet on Mainnet, or an exchange) and sends the
amount from Step 2 to the public key — a small test transfer first. You verify with `balance.sh
mainnet`. You never handle the purchase.

## Step 4 — Deploy

1. Set the mainnet gas limits and constructor arguments in the deploy script (Step 1 and 2), rebuild:
   `cargo odra build`.
2. Show the user exactly what is about to happen — contracts, arguments, payment limits, expected
   charge, the account paying — and **ask for a yes**.
3. `/odra-plugin:deploy-to-livenet` with `mainnet`. Addresses are saved to
   `resources/casper-contracts.toml`; commit that file.
4. Verify: `deploy.sh mainnet status`, one read through the CLI, and the package page
   `https://cspr.live/contract-package/<hash without "hash-">`.
5. If something failed midway, read the error before retrying: the deploy script is idempotent
   (`load_or_deploy` reuses what is already deployed), and every retry of an install costs again.

## Step 5 — The production web app

1. `${CLAUDE_SKILL_DIR}/../web-app/scripts/sync-contracts.sh` — writes
   `web/public/contracts.casper.json`.
2. Fund the reader account on mainnet with a few CSPR (see `web-app`, "The reader key"); ask first,
   it is a mainnet transfer.
3. `/odra-plugin:publish-web` with `mainnet`: it builds the page for mainnet and publishes it to
   the root of the project's GitHub Pages site, next to the testnet version under `/testnet/`
   (which stays, for trying things without real CSPR). It needs the site's CSPR.click app id —
   already in `GUIDE.md` if the testnet page was published — and the user's yes.
4. Check the live site as that skill says: state loads without a wallet; the user connects a
   mainnet account and performs one real action with a small amount.

## Step 6 — Tokens

If the project has a fungible token: `/odra-plugin:list-token` with `mainnet`. The liquidity the
user adds sets the opening price and is real money — the amounts are entirely their decision.

## Step 7 — After launch

Update `GUIDE.md` (or write it) with the mainnet facts: addresses and explorer links, the site URL,
which key is the deployer and where its backup is, how to upgrade (`deploy.sh mainnet upgrade
<Contract> --gas ...`, upgradable contracts only), and what to watch — the contract's page on
cspr.live shows every call. Remind the user that the deployer key now controls a live contract.

---

## Reference

- [Livenet backend](https://odra.dev/docs/backends/livenet) — configuration, gas handling, errors
- [Upgrading Contracts](https://odra.dev/docs/tutorials/upgrades)
- [Buying CSPR in Casper Wallet](https://www.casperwallet.io/user-guide/how-to-buy-cspr)
- [CSPR.build console](https://console.cspr.build) — CSPR.click app ids, CSPR.cloud tokens
