---
name: build-dapp
description: >
  Take a product idea in plain words to a working application on Casper: smart contracts written
  and tested, deployed to testnet, a web app connected to wallets, tokens made visible to the
  ecosystem, and a user who understands what was built and how to take it to mainnet. Requires no
  blockchain knowledge from the user. Use when the user describes an app, token, NFT, auction,
  game, marketplace, DAO, crowdfunding or similar to build "on Casper" / "on chain", says "build
  a dapp", "build me an app", "create a token with ...", "launch an NFT", or "build-dapp" — and
  whenever a request needs more than a single contract change.
allowed-tools: Skill, Read, Write, Edit, Bash, AskUserQuestion, WebFetch
---

# From an idea to a dapp on Casper

You are the builder and the guide. The user brings an idea and, possibly, no knowledge of
blockchains at all. They should end up with:

1. contracts that do what they asked, with tests that prove it;
2. those contracts running on **Casper testnet**, with explorer links;
3. a **web app** on their machine where they connect a wallet and use the thing;
4. their tokens visible where the ecosystem looks for them;
5. `GUIDE.md` in the project: what was built, how to use and test it, how to go to mainnet;
6. an understanding of each of those, built up along the way.

Each phase below hands off to a skill that knows the details. **Invoke the skill; do not redo its
work from memory.** Keep going from phase to phase without asking permission to continue — stop
only where a step is marked as the user's.

## How to work with a newcomer

- **Ask about the product, never about the technology.** "Should the losing bidders get their
  money back automatically, or claim it?" is a good question. "Do you want a pull-payment
  pattern?" is not. Decide technical matters yourself and say what you chose in one sentence.
- **At most one round of questions before building**, and only about things that change the
  product and that the request leaves open. State your assumptions and move on; the user can
  correct them when they see the result.
- **Teach at the moment of contact.** When a concept first matters — account, gas, testnet, package
  hash — explain it in two or three sentences from
  [`casper-primer.md`](./reference/casper-primer.md), using the user's project as the example. No
  lectures up front.
- **Show, with links.** Every deployment and transaction gets its explorer link. Seeing their
  contract on `testnet.cspr.live` teaches more than a paragraph.
- **Say what is theirs to do, and why.** A few steps need the human: installing a wallet, the
  faucet, approving a transaction, registering for an app id, buying CSPR. Give exact clicks,
  then wait and verify (`balance.sh`, the explorer) rather than taking their word or guessing.
- **Their keys and money are theirs.** You never see a recovery phrase, never type a password,
  never send mainnet CSPR without an explicit yes for that transaction.

---

## Phase 1 — Understand the idea

Restate the idea as a short specification in the user's words and get it confirmed (this is the one
round of questions). Cover:

- **Who does what** — the roles (owner, bidder, buyer, member...) and the actions of each.
- **What is owned** — a fungible token (CEP-18), NFTs (CEP-95), CSPR held by the contract.
- **If there are NFTs: what each one is** — its name, and where its picture comes from. An NFT
  without an `image` in its metadata shows as a blank card in wallets and explorers. If the user
  has no artwork yet, build so the owner can set an image address later, and say so.
- **Money flows** — who pays, who receives, when, and what happens to the money of people who do
  not win / cancel / are late. Every CSPR that enters a contract needs a way out.
- **Time** — deadlines, rounds, what happens when nobody acts. For anything recurring ("a new
  auction every day"): does the next round start on a fixed schedule or when the previous one is
  closed, and what happens to a round nobody took part in.
- **Rules for the owner** — what the creator may change later, and what nobody may.

Then translate, for yourself, into a design. Guidance that prevents the usual wrong turns:

- **Nothing happens by itself on a blockchain.** There are no timers: "the auction ends after 24
  hours" means the *next transaction after* the deadline settles it. Design every time-based rule
  as "anyone may call `settle` once the time is up, and every other action settles first". Tell the
  user this in plain words — it is the most surprising property for newcomers. One consequence to
  handle on the page: an action sent just after a deadline belongs to the *next* round.
- **Prefer one contract** unless there is a reason to split (an independent token others must hold,
  many instances from a factory). One contract means one deployment, one address, one client.
- **Use the standards.** A token is `Cep18`, an NFT collection is `Cep95` from `odra-modules`,
  embedded as a `SubModule`. Wallets and explorers recognise them without any extra work.
- **Make durations and prices constructor arguments.** A 24-hour auction cannot be tried out in an
  afternoon; deploy to testnet with 10-minute rounds and to mainnet with the real value.
- **Pay people back in the same transaction** where possible (the outbid bidder is refunded when
  the higher bid arrives) so that nobody has to come back and claim. Such a refund is a transfer
  to whoever paid in: if that could be a contract unable to receive CSPR, its refund would fail and
  block everyone after it. Either accept payments from accounts only (revert when
  `self.env().caller().is_contract()`), or let people claim refunds themselves. A call from the
  CLI or a wallet, also a payable one "through proxy", has the account as its caller.
- **Keep amounts that move at 2.5 CSPR or more** (minimum bid, price, refund): it is the smallest
  transfer between accounts on Casper, and smaller payouts are not worth finding the edge of.
- **Do not expose `renounce_ownership`** in a contract that pays its owner: without an owner the
  payout reverts and the funds are stuck.
- **Deploy upgradable** unless the user wants immutability; say which you chose and what it means.

## Phase 2 — Environment and project

1. `/odra-plugin:check-env` — install what is missing before going on, including its optional
   Node.js and `wasm-pack` rows (the web app needs them); Docker is not needed for this flow.
2. `/odra-plugin:new-project` — template by what is owned: `cep95` for NFTs, `cep18` for a
   fungible token, `full` otherwise. Name the project after the product, in `snake_case`.
3. Repeat check-env's Rust toolchain and wasm target checks from inside the new project: it pins
   its own toolchain.
4. `git add -A && git commit` the scaffold. Commit again after each phase that leaves the project
   working (tests green, deployed, web app building) — `go-mainnet` later requires a clean tree,
   and the user gets a history of how the app came to be. `resources/<chain>-contracts.toml` is
   committed; `keys/`, `*.env`, `target/` and `node_modules/` never are.

Explain while the first build runs: what a smart contract is, and that the project has three parts —
contracts (`src/`), a command line tool that deploys and calls them (`bin/cli.rs`), and soon a web
page (`web/`).

## Phase 3 — Contracts and tests

Invoke `smart-contract-writer` with the specification from Phase 1 (it will not need to ask again).
In this flow you run the commands yourself (`cargo odra test`, `cargo odra schema`) instead of
asking the user, you may write a new contract together with its tests rather than test-first, and
its "Output Format" section does not apply — the code goes into the project, the explanation to
the user comes in plain words. Read its core references and `gotchas.md` once, plus `cep95.md`
or `cep18.md` for the token, `events.md`, `errors.md` and `testing.md`; nothing else is needed for
a typical contract. Requirements to pass on:

- a test for every rule in the specification, including the unhappy paths (too low, too late, not
  allowed) and **the money**: assert balances before and after, and that the contract holds zero
  when everything is settled;
- time-based rules tested with `env.advance_block_time`;
- read-only entry points for everything the page will show (current state, deadlines, prices,
  owners) — the web app can only display what a getter returns;
- an event for every state change;
- the template's sample contract (`src/token.rs` / `src/flipper.rs`) deleted and replaced by the
  product's own module — do not build on top of `MyToken`; `Odra.toml`, `src/lib.rs` and the
  deploy script in `bin/cli.rs` updated; deployment upgradable; constructor arguments for durations
  and prices read from environment variables with production defaults (pattern in `cli.md`);
- a `gas_costs` test that runs one of each transaction and prints `env.gas_report()` (see
  `testing.md`);
- no unguarded `mint`/`burn` left over from a template.

Then `/odra-plugin:test-contracts` on **both** backends (`cargo odra test`, then
`cargo odra test -b casper`). Do not go on with a failing test.

Tell the user what the tests cover, as a list of the rules from their specification — this is their
evidence that the contract does what they asked.

## Phase 4 — Account and testnet deployment

1. `/odra-plugin:setup-account` for testnet. The faucet is the user's step: explain accounts, keys
   and test CSPR while they do it, then verify the balance yourself.
2. **Measure before paying.** Run the `gas_costs` test on the Casper VM
   (`cargo odra build && ODRA_BACKEND=casper cargo test gas_costs -- --nocapture`): it prints what
   the install and each call consume, within a fraction of a percent of the real network. Set the
   install's payment limit in the deploy script to that plus 15–20%. An install that runs out of
   gas is charged and has to be repeated; a limit far above the need costs a quarter of the excess.
3. `/odra-plugin:deploy-to-livenet` to testnet, with short durations so the user can watch a full
   cycle — 5 minutes per round is enough, and every minute is a minute of waiting below.
4. Exercise it from the CLI, as a first proof: one happy path through the main actions
   (`deploy.sh testnet contract <Contract> <entry point> ...`), then
   `tx-cost.sh testnet <hash>` for what each really cost. While a round runs out, go on with
   Phase 5 and come back to settle it.
5. Give the user the explorer link of the contract package
   (`https://testnet.cspr.live/contract-package/<hash without "hash-">`) and of one transaction,
   and explain what they are looking at.

## Phase 5 — Web app

`/odra-plugin:web-app`. The page is designed around what a visitor does (Phase 1's "who does
what"), in the user's vocabulary. Run it, and walk the user through connecting Casper Wallet on
Testnet and doing each action once. Their first approved transaction in their own app is the
moment the whole thing becomes real — do not skip it, and wait for them.

## Phase 6 — Make the tokens visible

Only if the project created tokens: `/odra-plugin:list-token`. A fungible token gets a liquidity
pool on CSPR.trade (testnet); NFTs are checked on the explorer and the wallet (or, without a
browser, with the CLI getters). Skip the phase, and
say so, for a project without tokens.

## Phase 7 — Hand over

Write `GUIDE.md` in the project root, for this project and this user — concrete names, addresses
and commands, not a generic tutorial:

1. **What you have** — one paragraph, then the parts: contract(s) with what each does, where they
   are deployed (explorer links), the web app, the token(s).
2. **How it works** — the rules, including who can do what and what happens to money, and the
   "nothing happens by itself" point where it applies.
3. **Try it** — start the web app; the wallet setup; a script of actions to perform and what to
   expect after each; where to see it on the explorer.
4. **Change it** — how to run the tests, redeploy or upgrade, regenerate the client.
5. **Accounts and keys** — which key files exist, what each is for (deployer, reader), which are
   secret, what must be backed up.
6. **Going to mainnet** — the checklist from `/odra-plugin:go-mainnet`, with this project's costs
   as measured on testnet, and what changes for real users.
7. **Words used** — a short glossary of only the terms this guide used.

Then tell the user, briefly: what exists, the links, how to open the app, and that
`/odra-plugin:go-mainnet` takes it live when they are ready. Do not deploy to mainnet as part of
this skill — it costs real money and is a separate decision.

---

## When something does not work

- A tool is missing or a build fails before any code was written → `/odra-plugin:check-env`.
- A contract does not compile or a test fails → `smart-contract-writer` (its `gotchas.md` first).
- A deployment fails → the error table in `deploy-to-livenet`; an account that was never funded
  shows up as `Couldn't get purse uref`.
- The page shows nothing → the table in `web-app`.
- Anything about Odra's API → [`docs-map.md`](../../reference/docs-map.md), then the page it
  names. Do not improvise an API.

Report honestly at every phase: what ran, what passed, what you could not check (anything needing
the user's wallet), what remains.
