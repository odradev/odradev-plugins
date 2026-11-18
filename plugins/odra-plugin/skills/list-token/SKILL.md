---
name: list-token
description: >
  Make the tokens of a project visible and usable in the Casper ecosystem: a fungible token
  (CEP-18) gets a liquidity pool on CSPR.trade, the Casper DEX, so it can be traded; NFTs (CEP-95)
  are checked on the explorer and in the wallet. Use when the user says "list the token", "make it
  tradable", "CSPR.trade", "casper trade", "add liquidity", "create a pool", "where can people buy
  my token", "show my NFT", or "list-token".
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/../deploy-to-livenet/scripts/*),Bash(${CLAUDE_SKILL_DIR}/../setup-account/scripts/*),Bash(cargo *),Bash(curl *),Bash(ls *),Bash(cat *),Bash(grep *),Read,Write,Edit,AskUserQuestion,WebFetch
---

# Put a token where the ecosystem can see it

What "listed" means depends on the kind of token:

| Token | Visible automatically | Needs this skill |
| --- | --- | --- |
| Fungible, CEP-18 | explorer (cspr.live), Casper Wallet balances | a **liquidity pool on CSPR.trade** to be tradable |
| NFT, CEP-95 | explorer: contract page, token pages, owners | nothing to deploy — verify and show the user |

The contract must already be deployed on the target network (`resources/<chain>-contracts.toml`).
Do testnet first; mainnet uses the same steps with real CSPR and the user's explicit yes.

---

## Fungible token — a pool on CSPR.trade

### Explain first

> CSPR.trade is an exchange without an order book. A token is tradable when a **pool** exists: a
> pot holding your token and CSPR side by side. Anyone can swap one for the other against the pot,
> and the ratio inside is the price. You open the pool by depositing both; **the ratio you deposit
> is the opening price** (1,000 tokens + 10 CSPR → 0.01 CSPR per token). The deposit stays yours:
> you receive "LP tokens" that redeem your share later. More in the pot means steadier prices; a
> tiny pool moves a lot with every trade.

Then ask (this is the user's money and their price, never yours to choose on mainnet):

- how many tokens and how much CSPR go into the pool — on testnet propose a small default such as
  1,000 tokens + 10 CSPR and go ahead;
- on mainnet also say the cost below and wait for a yes.

### Cost

| Step | Payment limit | Consumed (measured on testnet, 2026-11) |
| --- | --- | --- |
| `approve` | 5 CSPR | a few CSPR |
| first deposit — **creates the pool** (installs a pair contract) | 500 CSPR | about 410 CSPR |
| later deposits into the existing pool | 30 CSPR | under 10 CSPR |

Plus the deposit itself, which is not a fee. The account needs the deposit + the limits available.

### Add the scenario to the project

1. Copy [`reference/cspr_trade.rs`](./reference/cspr_trade.rs) to `src/cspr_trade.rs` and add
   `pub mod cspr_trade;` to `src/lib.rs`.
2. Paste [`reference/list_on_cspr_trade.rs`](./reference/list_on_cspr_trade.rs) into `bin/cli.rs`
   as its header says (crate name, token contract, `.scenario(ListOnCsprTrade)`).
3. `cargo build --bin <project>_cli`.

The scenario approves the router for the token amount, then calls the router's payable
`add_liquidity_cspr` with the CSPR attached. The router creates the pool on the first call.

### Run it

Amounts are in the smallest units: tokens × 10^decimals, CSPR × 10^9 (motes).

```bash
# 1,000 tokens (9 decimals) + 10 CSPR, first deposit:
${CLAUDE_SKILL_DIR}/../deploy-to-livenet/scripts/deploy.sh testnet scenario list_on_cspr_trade \
  --token_amount 1000000000000 --cspr_amount 10000000000
# later deposits: add  --gas 30000000000
```

The deploying account must hold the tokens (it does if `init` minted the initial supply to the
deployer) and the CSPR.

### Verify and show the user

- The output ends with `Deposited ... received ... LP tokens`.
- The exchange's index knows the token and the pair within a minute or two:
  ```bash
  curl -s https://cspr-trade-api.dev.make.services/tokens | grep -c <package hash without "hash-">   # testnet
  curl -s https://api.cspr.trade/tokens | grep -c <package hash without "hash-">                      # mainnet
  ```
- Send the user to <https://testnet.cspr.trade> (mainnet: <https://cspr.trade>), Pool page, to see
  the pair and try a swap with their wallet.

Say these things plainly:

- A new token is **not whitelisted** (`is_whitelisted: false` in the API). The pool exists and
  works on chain; how prominently the site shows a non-whitelisted token, and how a token gets
  whitelisted or a logo, is decided by the CSPR.trade team and is not documented. Point the user to
  the CSPR.trade / Casper community channels for that; do not promise it.
- Give the token a proper `name` and `symbol` before deploying — the pool is named after them
  (`CSPR.trade: Wrapped CSPR - <name>`), permanently.
- Use 9 decimals unless there is a reason not to: it matches CSPR and keeps amounts readable.

### When it fails

| Error | Meaning |
| --- | --- |
| `Expired` (21001) | the transaction was included after its 20-minute deadline; run again |
| `InsufficientAAmount` / `InsufficientBAmount` (21002/21003) | the pool exists with a different ratio than the amounts given; deposit in the pool's current ratio |
| `InsufficientAllowance` / `InsufficientBalance` from the token | the account lacks the tokens, or the token restricts `transfer_from` |
| `Out of gas` on the first deposit | creating the pool needs the 500 CSPR limit |
| `No contract code registered for contract-package-…` | a getter of the router or factory was called — only transactions can be sent to an external contract from the CLI |

The router addresses are in the scenario (`casper-test` and `casper`). They are the ones the
official CSPR.trade SDK uses; if a call fails with `No such contract`, check the current ones in
<https://github.com/make-software/cspr-trade-mcp> (`packages/sdk/src/config.ts`).

## NFTs — verify and show

Nothing more to deploy: explorers index CEP-95 contracts by themselves.

1. Mint at least one token on testnet (through the app or the CLI).
2. Show the user the contract package page —
   `https://testnet.cspr.live/contract-package/<hash without "hash-">` — where the NFTs, owners and
   transfers appear a minute or two after the mint.
3. Metadata is what makes an NFT look like something: the `name`, `description` and `image` (a
   public https or ipfs URL) keys of the token metadata. A token without an `image` shows as a
   blank card. If the project's NFTs have no image yet, say so and offer to add one.
4. Without a browser, verify with the CLI instead and say the explorer view is unchecked:
   `deploy.sh testnet contract <Contract> owner_of --token_id <id>`, `... token_metadata --token_id
   <id>`, and `deploy.sh testnet print-events <Contract>` for the `Mint` event.
5. An NFT **marketplace** listing is not something to promise: CSPR.market documents support for
   the older CEP-78 and CEP-47 standards, and CEP-95 support was announced as in progress. Check
   <https://testnet.cspr.market> for the collection and report what you actually see.

---

## Reference

- [CSPR.trade: providing liquidity](https://www.casper.network/get-started/casper-101-how-to-provide-liquidity-on-cspr-trade)
- [odradev/casper-trade](https://github.com/odradev/casper-trade) — the DEX contracts (Odra):
  `router.rs` for every entry point (swaps, `remove_liquidity_cspr`, quotes)
- [CEP-18 reference](../smart-contract-writer/reference/cep18.md),
  [CEP-95 reference](../smart-contract-writer/reference/cep95.md)
