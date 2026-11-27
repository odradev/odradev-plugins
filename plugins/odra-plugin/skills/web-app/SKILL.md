---
name: web-app
description: >
  Build the web front end of an Odra project: a page that reads the deployed contracts and sends
  transactions through the user's wallet (CSPR.click, Casper Wallet). Generates the TypeScript
  client with `cargo odra generate-client` and scaffolds a Vite app around it. Use when the user
  says "web app", "frontend", "UI", "website for the contract", "connect a wallet", "CSPR.click",
  "generate client", "dapp page", or "web-app".
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/*),Bash(cargo odra *),Bash(npm *),Bash(npx *),Bash(node *),Bash(ls *),Bash(cat *),Bash(grep *),Read,Write,Edit,AskUserQuestion,WebFetch
---

# Web app for an Odra project

The result is a static site in `web/`: no server of your own, no API keys. It talks to the chain in
two ways, and both are already wired in the template:

| | How | Needs a wallet |
| --- | --- | --- |
| **Reading** contract state | the generated client simulates the getter on a node (`speculative_exec`) through the public proxies at `*-rpc.odra.dev` | no |
| **Writing** (transactions) | the generated client builds the transaction, [CSPR.click](https://docs.cspr.click) asks the user's wallet to sign and sends it | yes |

**Prerequisites:** the contracts are deployed to testnet (`resources/casper-test-contracts.toml`
exists — `/odra-plugin:deploy-to-livenet`), Node.js 20.19+, `wasm-pack`
(`cargo install wasm-pack`) and a project on **Odra 2.11 or newer** — the client generated for
2.10 hangs on some reads, and `build-client.sh` refuses it; bump `odra*` in `Cargo.toml` first
([migration guide](https://odra.dev/docs/migrations/to-2.11.0)).


**Without testnet:** the page can be developed against a local NCTL node — reads only, since
wallets do not send transactions to a local network. Run `/odra-plugin:setup-nctl`, then its
`enable-speculative.sh` (a plain NCTL node serves neither `speculative_exec` nor cross-origin
requests), deploy with `deploy.sh nctl`, fund the reader account there, and start the page with
`VITE_NETWORK=nctl npm run dev`. Useful for building the page before the user has test CSPR; the
wallet flow still has to be checked on testnet.

On NCTL, test the writes with the project's CLI (`deploy.sh nctl <entry point> ...`). Then check
that the page shows the new state after its next refresh: that proves the reads and the rendering
of every action. **Do not build a signer into the page or the dev server** to make the buttons
work on NCTL. It is code the user did not ask for, it signs with keys outside the wallet, and it
is not what the published site does. Tell the user plainly that the buttons need a wallet and are
tried on testnet.

---

## Step 1 — Generate the contract client

From the project root:

```bash
${CLAUDE_SKILL_DIR}/scripts/build-client.sh
```

It runs `cargo odra generate-client`, which writes `<project>_client/pkg-web/`: one
`<Contract>WasmClient` class per contract in `Odra.toml`, with a method per entry point, plus the
events, the error enums (`<Contract>Errors`) and the number types (`U256`, `U512`, `Address`).
**Read `<project>_client/pkg-web/<project>_wasm_client.d.ts` before writing any page code** — it is
the exact API, and it is generated, so never guess a method name.

Run it again after every change to an entry point, event or error. It regenerates the contract
schemas itself (no separate `cargo odra schema`), and keeps the client crate's `target/` out of
git. Commit `<project>_client/` without `pkg-web/` and `target/`: both are build output.

### The reader key

A read is a simulated call, and a call has a sender. The script creates
`keys/reader_secret_key.pem` for that and compiles it into the client. Consequences to respect and
to tell the user:

- **The reader key is public** — it ships inside the `.wasm` file every visitor downloads. It is a
  throwaway key. Never reuse the deployer key, never send it more than a few CSPR.
- `keys/` must be git-ignored (the script warns if not).
- **Fund the reader account once per network** with a few CSPR, from the deployer account. The
  CLI's `transfer` takes an account hash, not a public key:
  ```bash
  READER=$(${CLAUDE_SKILL_DIR}/../setup-account/scripts/account-hash.sh keys/reader_secret_key.pem)
  ${CLAUDE_SKILL_DIR}/../deploy-to-livenet/scripts/deploy.sh testnet transfer --to "$READER" --amount "5 cspr"
  ```
  Reads are simulated and cost nothing, but the node refuses to simulate for an account that does
  not exist (`no such addressable entity`). 2.5 CSPR is the smallest possible transfer and enough.
- Without the script, `cargo odra generate-client` builds a client with no key and every read fails
  with `WASM_CLIENT_SK was empty at build time`. The script sets `WASM_CLIENT_SK` to the contents
  of the key file.

## Step 2 — Scaffold `web/`

```bash
${CLAUDE_SKILL_DIR}/scripts/new-web-app.sh <MainContract> "Page title"
${CLAUDE_SKILL_DIR}/scripts/sync-contracts.sh
cd web && npm install
```

`sync-contracts.sh` copies the deployed addresses from `resources/<chain>-contracts.toml` to
`web/public/contracts.<chain>.json`; run it after every deploy. What you get:

| File | Role | Edit? |
| --- | --- | --- |
| `src/network.ts` | testnet/mainnet endpoints, explorer links, CSPR.click app id | only to add a network setting |
| `src/casper.ts` | starts the client and CSPR.click, account tracking, `send`, `parseCspr`, `formatCspr` | no |
| `src/main.ts` | the page logic — a working skeleton for `<MainContract>` | **yes, this is the app** |
| `index.html`, `src/style.css` | the page | **yes** |

## Step 3 — Write the page

Design the page from what a visitor wants to do, not from the list of entry points: the state they
care about at the top, the one or two actions as buttons or forms, technical detail (hashes,
explorer links) at the bottom. Use the words of the user's request, not contract vocabulary.

In `main.ts`:

- **Reads** go in `refresh()`: call `prepareRead()` once, then `await contract.<getter>()`. Getters
  return typed values — `U512`/`U256` objects (not numbers), `Address | undefined` for an `Option`,
  `bigint` for `u64`. An `Address` is shown with `.value` (`address.toString()` is JSON); build one
  from the connected account with `account.address`, numbers with `U256.fromBigInt(1n)`. An
  address reads `entity-account-<hex>` or `hash-<hex>`; link it with `addressUrl()` from
  `network.ts`, and compare it with `currentAccount()?.address.value` to mark "you".
- **A client call frees every `Address`, `U256` and `U512` passed to it.** The `.d.ts` does not
  say so (`balanceOf(address: Address)`), but the object is moved into the call. Use it again
  (`balanceOf(me)` and then `me.value`, or the same `Address` in a second call) and the page stops
  with `null pointer passed to rust`. Keep addresses as strings and amounts as `bigint`, and build
  a fresh object for each call: `const addr = (s: string) => new Address(s)`, then
  `contract.balanceOf(addr(me))`. Values *returned* by a getter are yours to keep.
- **A getter that reverts rejects its promise.** Where "not there" is an expected answer, wrap
  the read: `await readOr([], () => contract.tokenMetadata(id))`. Of the `Cep95` getters,
  `tokenMetadata` and `approvedFor` revert for a token that does not exist (`User(40005)`);
  `ownerOf` answers `undefined` and `balanceOf` zero, also before anything was minted, and need no
  wrapper. Do not wrap everything: `readOr` hides a network failure as well.
- Reads are slow (about a second each, one network round trip per getter). Read what the page
  shows, not everything the contract has; refresh on a timer of tens of seconds, not every second.
- **Writes** go through `transact(() => send(<gas in CSPR>, () => contract.<entryPoint>(args)))`.
  It asks the user to connect if needed, shows progress in the status line and calls `refresh()`
  on success.
- A **payable** entry point takes the attached CSPR as an extra last argument:
  `contract.bid(amount)` with `amount: U512` in motes. Build it with `parseCspr(input.value)` —
  never multiply a float.
- **Gas** is a ceiling in CSPR, not the price; three quarters of the unused part is refunded. Take
  what the call consumed on testnet (`tx-cost.sh testnet <hash>` from `deploy-to-livenet`, or the
  `gas_costs` test) and use about twice that: calls of one entry point vary with the state they
  meet. Simple calls consume 3–7 CSPR. Too little fails with `Out of gas`.
- **Errors**: map `result.errorCode` against the generated `<Contract>Errors` enum in
  `describeError()` so the user reads a sentence, not a number.
- **Amounts**: 1 CSPR = 1,000,000,000 motes. Show CSPR (`formatCspr`), send motes.
- **Time**: block time is in milliseconds since the Unix epoch, comparable with `Date.now()`.
- More contracts on one page: `new <Other>WasmClient(casper.client, casper.contracts.get("<Other>").address)`.

Things that break the wallet connection — the template gets them right, keep them that way:

- `startCasper()` runs the client's `init()` **before** it adds the CSPR.click script. The client
  listens for `csprclick:loaded`; loaded the other way round, sign-in events never arrive.
- `<div id="csprclick-ui">` stays in `index.html`, outside `#root`.
- The page must be served over `http://localhost` or `https://`. Opening `index.html` from disk
  does not work.

## Step 4 — Run and check it

```bash
cd web && npm run build      # type-checks against the generated client, then bundles
npm run dev                  # http://localhost:5173
```

`npm run build` must pass before you say the app works. `npm install` may warn that esbuild's
install script is not approved; the build works regardless.

Then prove the reads without a browser — the same client, key, proxies and address the page uses:

```bash
node ${CLAUDE_SKILL_DIR}/scripts/check-reads.mjs <MainContract> <getter> [<getter> ...]
# DailyAuction hash-8526… on casper-test
#   currentRound: 2n
#   minBid: 1000000000
```

(camelCase names of getters without arguments.) Run it from the project root, after the reader
account is funded.

Running the dev server from an agent: it does not return, so start it in the background and keep
its PID (`npm run dev > /tmp/web-dev.log 2>&1 & echo $!`), and stop it with `kill <PID>` — a
`pkill -f` pattern also matches the shell running it. The port is fixed at 5173; if it is taken,
`npm run dev -- --port 5180` (the development CSPR.click id works on any localhost port). When
checking with `curl`, look at content, not the status code: fetch `contracts.casper-test.json` and
see your contract's name — another project's server answers 200 as well.

Then **open the page in a headless browser before you say it works**. A build that passes and
reads that answer do not mean the page starts: a runtime error in `main.ts` leaves a blank or
half-drawn page, and only a browser shows it. With the dev server running:

```bash
cd web && npm install --no-save playwright@1.49.1 && npx playwright install chromium   # once
node ${CLAUDE_SKILL_DIR}/scripts/check-page.mjs http://localhost:5173 --expect "<text the page shows once state has loaded>"
```

It fails on an uncaught error, an error in the console, a failed request or a missing expected
text, and saves a screenshot (`/tmp/check-page.png`; look at it). Use one `--expect` per piece of
state the page shows without a wallet: a heading, a balance label, a form title. Fix every
problem it reports and run it again. If Chromium cannot run here (`npx playwright install
--with-deps chromium` needs root for its system libraries), say that the page is **unchecked in a
browser** and ask the user to open it and tell you what they see. Do not call it working.

Then check in a browser, in this order, and report each honestly:

1. The page loads and shows contract state **without a wallet** (`check-page.mjs` above) — this
   proves the addresses, the reader key and the reads.
2. **Connect wallet** opens the CSPR.click sign-in dialog (Casper Wallet, Ledger, MetaMask). The user needs the Casper Wallet extension, switched to
   **Testnet**, with an account that holds test CSPR (`/odra-plugin:setup-account`).
3. One transaction per action, approved in the wallet; the status line links to the explorer and
   the state on the page changes.

Steps 2 and 3 need the user's wallet: you cannot approve a transaction for them.

When a read fails, open the browser console; the usual causes:

| Message | Cause |
| --- | --- |
| `null pointer passed to rust` | an `Address`/`U256`/`U512` was used again after a client call freed it: build a fresh one per call (Step 3) |
| `WASM_CLIENT_SK was empty at build time` | client built without `build-client.sh` |
| `no such addressable entity` | the reader account has never been funded on this network |
| `RuntimeError: unreachable`, and the page waits forever | the client was built with odra-wasm-client 2.10: bump the project to Odra 2.11, delete `<project>_client/Cargo.lock`, run `build-client.sh` |
| `Speculative execution failed for '<getter>': ... User(<code>)` | the getter reverted with that contract error — expected for a missing item, wrap in `readOr` |
| `missing field` when loading `contracts.<chain>.json` | the file was written by hand; use `sync-contracts.sh` |
| the `.wasm` request fails in `npm run dev` | `server.fs.allow` was removed from `vite.config.ts` (the client lives outside `web/`) |
| `Failed to fetch` / 404 for `contracts.<chain>.json` | `sync-contracts.sh` not run after the deploy |
| a contract error on a getter | the deployed contract is older than the client: redeploy or upgrade, then sync |

## Step 5 — Explain what the user is looking at

Tell the user how to open it, what a visitor needs (Casper Wallet on Testnet + test CSPR), and
that the site is plain static files: `npm run build` writes `web/dist/`, which any static host
serves.

**To put it online use `/odra-plugin:publish-web`** — it publishes the testnet and the mainnet
version to GitHub Pages. Two things it takes care of, and that a hand-made publish must not skip
(the site would load and then fail to connect):

- The CSPR.click app id `csprclick-template` works **on localhost only**. The user registers the
  app at <https://console.cspr.build> (free) and the site is built with
  `VITE_CSPR_CLICK_APP_ID=<their id>`.
- The mainnet site is built with `VITE_NETWORK=mainnet`, after `/odra-plugin:go-mainnet` deployed
  the contracts. Fund the reader account on mainnet too.

---

## Reference

- [Wasm-Client](https://odra.dev/docs/advanced/wasm-client) — the generated client
- [CSPR.click documentation](https://docs.cspr.click) ([index for agents](https://docs.cspr.click/llms.txt))
  — providers, UI options, the events behind `casper.ts`
- [`docs-map.md`](../../reference/docs-map.md) — index of the Odra documentation
