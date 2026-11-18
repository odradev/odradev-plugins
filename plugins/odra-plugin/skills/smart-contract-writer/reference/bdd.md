# Scenario tests (BDD)

The rules of a contract are tested as **scenarios** written in plain sentences, so the person who
asked for the contract can read the tests and say "yes, that is what I meant" — and so the next
agent reads what the contract must do before reading how.

```gherkin
Scenario: The highest bidder wins the NFT and the owner is paid
  When Alice bids 10 CSPR
  And Bob bids 15 CSPR
  Then Alice has 100 CSPR
  When 1 day passes
  And Alice settles the auction
  Then Bob owns NFT 0
  And Owner has 15 CSPR
```

This is the default for a project made with this plugin. It runs on
[cucumber](https://cucumber-rs.github.io/cucumber/main/) with Odra's `odra-bdd` crate, on OdraVM and
on CasperVM, as part of `cargo odra test`. Needs Odra 2.11.

## The files

`test-contracts/scripts/add-bdd.sh` creates them (`new-project` runs it); never write the wiring by
hand.

| File | What it is | Edit? |
| --- | --- | --- |
| `tests/features/*.feature` | the scenarios, one file per area of the product | **yes — this is the specification** |
| `tests/steps/<area>.rs` | what each sentence does: one Rust function per sentence | **yes** |
| `tests/steps/common.rs` | sentences every feature can use: CSPR balances, time, expected failures | add to it |
| `tests/common/world.rs` | `TestWorld`: the test environment and the contracts of one scenario | **yes — add the contracts** |
| `tests/common/params.rs` | values read out of a sentence (`{span}`: `1 day`) | add to it |
| `tests/bdd.rs` | the runner | no |
| `Cargo.toml` | `[[test]] name = "bdd"`, `harness = false`; dev-dependencies `odra-bdd`, `cucumber` | no |

A new file in `tests/steps/` needs its `mod <area>;` line in `tests/steps/mod.rs`. Delete
`tests/features/example.feature` when the first real feature exists.

## Order of work

1. **Write the feature file first**, from the specification, in the words the user used. One
   `Scenario` per rule, the unhappy paths included. Show it to the user when they are there to
   read it: it is cheaper to correct a sentence than a contract.
2. Add the contract to `TestWorld` and write the steps the sentences need.
3. Run it, see it fail for the right reason, write the contract, see it pass.

## The world

One `TestWorld` is created per scenario, so every scenario starts on an empty chain. A contract
is an `Option` that a `Given` step fills — the feature file then says what was deployed, with which
settings:

```rust
// tests/common/world.rs
use daily_auction::auction::{DailyAuction, DailyAuctionHostRef, DailyAuctionInitArgs, Error};
use odra::casper_types::U512;
use odra::host::{Deployer, HostEnv};
use odra_bdd::{bdd_env::BDDEnv, types::account::Account};

pub struct TestWorld {
    pub bdd: BDDEnv,
    pub last_result: Option<OdraResult<()>>,
    auction: Option<DailyAuctionHostRef>,          // added; `auction: None` in `new()`
}

impl TestWorld {
    pub fn deploy_auction(&mut self, round_duration: u64, min_bid: U512) {
        self.bdd.set_caller(&Account::OWNER);
        self.auction = Some(DailyAuction::deploy(
            self.bdd.env(),
            DailyAuctionInitArgs { name: "Daily".to_string(), symbol: "DAY".to_string(), round_duration, min_bid },
        ));
    }

    pub fn auction(&mut self) -> &mut DailyAuctionHostRef {
        self.auction.as_mut().expect("no auction: the scenario needs `Given an auction with ...`")
    }

    pub fn error(name: &str) -> OdraError {
        match name {
            "BidTooLow" => Error::BidTooLow.into(),          // every error a feature names
            "BidBelowMinimum" => Error::BidBelowMinimum.into(),
            other => panic!("unknown error name in a feature file: {other}"),
        }
    }
}
```

`world.bdd` (`odra_bdd::bdd_env::BDDEnv`) is the test environment by names: `set_caller(&account)`,
`get_address(&account)`, `set_balance`, `get_balance`, and `env()` for the `HostEnv` with everything
in [`testing.md`](./testing.md).

## Steps

A step is a function with the sentence above it. `{...}` are typed values, in the order of the
arguments:

```rust
// tests/steps/auction.rs
use crate::common::{params::Span, world::TestWorld};
use cucumber::{given, then, when};
use odra::casper_types::U256;
use odra::host::HostRef;                 // with_tokens
use odra::prelude::Addressable;          // address()
use odra_bdd::types::{account::Account, cspr::CSPRAmount};

#[given(expr = "an auction with rounds of {span} and a minimum bid of {cspr_amount} CSPR")]
fn auction(world: &mut TestWorld, round: Span, min_bid: CSPRAmount) {
    world.deploy_auction(round.millis(), min_bid.amount());
}

#[when(expr = "{account} bids {cspr_amount} CSPR")]
fn bid(world: &mut TestWorld, account: Account, amount: CSPRAmount) {
    world.bdd.set_caller(&account);
    world.auction().with_tokens(amount.amount()).bid();
}

#[when(expr = "{account} tries to bid {cspr_amount} CSPR")]
fn try_bid(world: &mut TestWorld, account: Account, amount: CSPRAmount) {
    world.bdd.set_caller(&account);
    let result = world.auction().with_tokens(amount.amount()).try_bid();
    world.record(result);
}

#[then(expr = "{account} owns NFT {int}")]
fn owns_nft(world: &mut TestWorld, account: Account, token_id: u64) {
    let owner = world.auction().owner_of(U256::from(token_id));
    assert_eq!(owner, Some(world.bdd.get_address(&account)));
}

#[then(expr = "the auction holds {cspr_amount} CSPR")]
fn auction_holds(world: &mut TestWorld, amount: CSPRAmount) {
    let auction = world.auction().address();
    assert_eq!(world.env().balance_of(&auction), amount.amount());
}
```

| In a sentence | Rust type | Reads |
| --- | --- | --- |
| `{account}` | `odra_bdd::types::account::Account` | `Owner` (account 0, the deployer), `Alice`, `Bob`, `Charlie`, `Dave`, `Eve` |
| `{cspr_amount}` | `odra_bdd::types::cspr::CSPRAmount` | `10`, `0.5`, `roughly 3.3`, `5 Motes`; `.amount()` is `U512` motes |
| `{span}` | `Span` in `tests/common/params.rs` | `10 seconds`, `30 minutes`, `2 hours`, `1 day`; `.millis()` |
| `{int}`, `{word}`, `{string}` | `u64` (any integer), `String`, `String` | a number, one word, `"quoted text"` |

Already in `tests/steps/common.rs`:

| Sentence | Meaning |
| --- | --- |
| `Given Alice has 100 CSPR` | Alice's balance is counted from 100 from here on |
| `Then Alice has 85 CSPR` | 100, minus what she paid, plus what she received |
| `When 1 day passes` / `When 3 days pass` | block time moves forward |
| `When Alice sends 2.5 CSPR to Bob` | a plain transfer |
| `Then it fails with BidTooLow` | the `tries to ...` step before ended with that contract error |
| `Then it fails` / `Then it succeeds` | the same, without naming the error |

### Actions that must fail: `tries to`

A plain action step calls the entry point (`bid()`); if the contract reverts, the step fails and
the scenario stops there, showing the error. For a rule that says "this is refused", write a second
step that says **`tries to`**, calls the `try_` twin and hands the result to `world.record(..)`:

```gherkin
Scenario: A bid must beat the highest bid
  When Alice bids 5 CSPR
  And Bob tries to bid 5 CSPR
  Then it fails with BidTooLow
  And Bob has 100 CSPR
```

Do not make every action a `tries to`: a scenario whose `When` failed silently goes on to check
state that proves nothing.

### A token amount

`{cspr_amount}` is CSPR. For a CEP-18 token add a parameter of its own to `tests/common/params.rs`
— `TokenAmount<DECIMALS>` does the parsing without floats:

```rust
use cucumber::Parameter;
use odra::casper_types::U256;
use odra_bdd::types::token_amount::TokenAmount;
use std::str::FromStr;

/// An amount of the project's token, 9 decimals: `1000`, `0.5`.
#[derive(Debug, Clone, Copy, Parameter)]
#[param(name = "tokens", regex = r"\d+(?:\.\d+)?")]
pub struct Tokens(TokenAmount<9>);

impl Tokens {
    pub fn amount(&self) -> U256 {
        self.0.amount()
    }
}

impl FromStr for Tokens {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        TokenAmount::<9>::from_str(s).map(Tokens)
    }
}
```

and use it as `{tokens}`: `#[then(expr = "{account} has {tokens} DAY")]`.

## Writing good scenarios

- **The words of the user, not of the code.** "Alice bids 10 CSPR", not "Alice calls bid with
  10000000000". Amounts in CSPR, time in days and minutes, people by name.
- **One rule per scenario**, named as the rule: "A bid must beat the highest bid". The names are
  the list of what the contract guarantees.
- **`Given`** sets the scene, **`When`** is what somebody does, **`Then`** is what must be true.
  `And` repeats the keyword before it. What every scenario of a file starts with goes in
  `Background`.
- **Follow the money.** Give the actors a balance in `Background`, then state what each of them
  and the contract holds at the end.
- Reuse sentences. Before writing a step, look for one that already says it; ten scenarios should
  need a handful of steps.
- The same rule with several sets of numbers is a `Scenario Outline` with an `Examples` table.
- Keep a step thin: set the caller, call the contract, assert. Logic shared by steps is a method
  of `TestWorld`.

## Traps

- **`{account}` matches any single word.** `Then nobody owns NFT 0` collides with
  `{account} owns NFT {int}` ("Step match is ambiguous"). Phrase the second differently:
  `NFT 0 has no owner`.
- **`Then Alice has 85 CSPR` needs a `Given Alice has ... CSPR` first** — balances are counted from
  what the scenario set. Without it the step fails with `No CSPR balance was set for ...`.
- **Gas does not show in balances** on OdraVM or CasperVM, so "has 85 CSPR" is exact. On a live
  network the caller also pays for gas.
- A sentence with no step fails the run with `Step doesn't match any function`; a typo in a feature
  file is therefore an error, not a skipped test.
- A `HostRef` is not `Clone`: take what is needed (`world.auction().address()`) before borrowing
  `world` again.
- `cucumber` in `Cargo.toml` must stay the version `odra-bdd` uses (the script picks it); a
  different one fails with trait errors on `{account}`.
- In a workspace the scenarios belong to one contract crate: `add-bdd.sh <crate-dir>`, and that
  crate's `tests/` reaches the other crates as dev-dependencies.

## What stays a Rust `#[test]`

Things nobody would state as a rule of the product, in the contract's `#[cfg(test)] mod tests`:
the `gas_costs` report, an upgrade's migration, arithmetic of an internal helper, a property
checked over many values. See [`testing.md`](./testing.md). Do not write the same rule twice.

## Running

```bash
cargo odra test                              # unit tests, then the scenarios, on OdraVM
cargo odra test -b casper                    # the same on CasperVM
cargo test --test bdd                        # only the scenarios
cargo test --test bdd -- "highest bidder"    # scenarios whose name (or feature name) contains the text
```

A `✔` per step; a failing step shows the sentence, its line in the feature file, the step function
and the panic message, and the run exits with an error.
