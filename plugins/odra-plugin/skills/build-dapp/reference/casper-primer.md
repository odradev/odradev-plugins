# Casper in plain words

What a person needs to understand to own a dapp on Casper, in the order the questions come up.
Use these explanations when teaching; adapt the examples to the user's project. Do not recite the
whole file — explain a concept at the moment the user meets it.

## The network

- **Blockchain** — a shared database run by many independent computers (*validators*). Nobody can
  edit it privately; everything changes through signed *transactions* that everyone can verify.
- **Casper** — one such network. Its currency is **CSPR**. The smallest unit is the **mote**:
  1 CSPR = 1,000,000,000 motes. Contracts and tools count in motes; people read CSPR.
- **Mainnet** — the real network; CSPR there has a market price. Chain name `casper`.
- **Testnet** — a full public copy for trying things out. Test CSPR is free (the faucet) and
  worthless. Chain name `casper-test`. What works on testnet works the same on mainnet.
- **Local node (NCTL)** — a private network in Docker on your machine, for fast experiments.
- **Block explorer** — a website showing everything on the network: <https://cspr.live> (mainnet),
  <https://testnet.cspr.live> (testnet). Every account, contract and transaction has a page.

## Accounts

- **Account** — a key pair. The **secret key** (a `.pem` file, or a wallet's recovery phrase)
  controls it; there is no password reset. The **public key** is the shareable address.
- **Wallet** — an app holding secret keys and asking you to approve each transaction.
  **Casper Wallet** is the standard browser extension.
- **CSPR.click** — the "Connect wallet" button of Casper websites: one integration that works with
  Casper Wallet, Ledger and others.
- An account exists on the network only after it has received CSPR once.

## Contracts

- **Smart contract** — a program stored on the network, with its own data and, optionally, its own
  CSPR balance. Anyone can call it; it does exactly what its code says, for everyone.
- **Entry point** — a function of the contract that can be called. Reading is free; changing
  state is a transaction and costs a fee.
- **Deploying / installing** — uploading the program. It gets an address, the **package hash**
  (`hash-…`), which never changes, also across upgrades.
- **Upgradable or locked** — decided at the first deploy. An upgradable contract can get new code
  from the account that installed it (so its users trust that account); a locked one can never
  change, bugs included.
- **Gas** — the fee for a transaction, paid in CSPR by the sender. You state a ceiling; most of
  what is not used comes back. Storing data is the expensive part, which is why installing a
  contract costs far more than calling it.
- **Events** — messages a contract emits when something happens (a bid, a transfer). Apps and
  explorers show history from them.
- **Odra** — the Rust framework the contracts are written in. It also gives the tests, the command
  line tool that deploys them, and the TypeScript client the web page uses.

## Tokens

- **Fungible token (CEP-18)** — interchangeable units with balances, like a currency or points.
- **NFT (CEP-95)** — unique items, each with an id, an owner and metadata (name, image link).
- Wallets and explorers recognise these standards automatically, so a token built on them shows
  up in users' wallets without further work.
- **DEX (CSPR.trade)** — a marketplace of *liquidity pools*: pairs of tokens deposited by anyone,
  against which anyone can swap. A token becomes tradable when someone creates a pool for it by
  depositing the token together with CSPR; the ratio of the two deposits is the starting price.

## Safety rules worth repeating to a newcomer

- Never share a secret key or recovery phrase; no legitimate tool or person asks for it.
- Keep separate keys for testnet and mainnet.
- A transaction cannot be undone. On mainnet, read the wallet prompt before approving.
- A contract holding other people's CSPR deserves a second pair of eyes before mainnet.
