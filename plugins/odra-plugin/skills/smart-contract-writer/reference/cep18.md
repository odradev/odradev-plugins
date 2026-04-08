# CEP-18 Fungible Token Standard

Odra implements the CEP-18 Casper Fungible Token Standard (analogous to ERC-20) through
the `odra_modules::cep18_token::Cep18` module. Use it as a `SubModule` to add fungible
token capabilities to any contract.

## Quick Start

```rust
use odra::casper_types::U256;
use odra::prelude::*;
use odra_modules::cep18_token::Cep18;

#[odra::module]
pub struct MyToken {
    token: SubModule<Cep18>,
}

#[odra::module]
impl MyToken {
    pub fn init(&mut self, name: String, symbol: String, decimals: u8, initial_supply: U256) {
        self.token.init(symbol, name, decimals, initial_supply);
    }

    delegate! {
        to self.token {
            fn name(&self) -> String;
            fn symbol(&self) -> String;
            fn decimals(&self) -> u8;
            fn total_supply(&self) -> U256;
            fn balance_of(&self, address: &Address) -> U256;
            fn allowance(&self, owner: &Address, spender: &Address) -> U256;
            fn approve(&mut self, spender: &Address, amount: &U256);
            fn transfer(&mut self, recipient: &Address, amount: &U256);
            fn transfer_from(&mut self, owner: &Address, recipient: &Address, amount: &U256);
        }
    }
}
```

## Initialization

```rust
pub fn init(
    &mut self,
    symbol: String,
    name: String,
    decimals: u8,
    initial_supply: U256
)
```

- `initial_supply` is minted to the caller

## CEP-18 Interface Methods

### Query Methods

| Method | Returns | Description |
|---|---|---|
| `name()` | `String` | Token name |
| `symbol()` | `String` | Token symbol |
| `decimals()` | `u8` | Decimal places |
| `total_supply()` | `U256` | Total token supply |
| `balance_of(address: &Address)` | `U256` | Balance of an account |
| `allowance(owner: &Address, spender: &Address)` | `U256` | Approved spending amount |

### Mutation Methods

| Method | Description |
|---|---|
| `transfer(recipient: &Address, amount: &U256)` | Send tokens from caller to recipient |
| `transfer_from(owner: &Address, recipient: &Address, amount: &U256)` | Spend from allowance |
| `approve(spender: &Address, amount: &U256)` | Set spender's allowance |
| `increase_allowance(spender: &Address, inc_by: &U256)` | Increase allowance (saturating) |
| `decrease_allowance(spender: &Address, decr_by: &U256)` | Decrease allowance (floors at zero) |
| `mint(owner: &Address, amount: &U256)` | Mint new tokens (requires MintAndBurn modality + Minter/Admin badge) |
| `burn(owner: &Address, amount: &U256)` | Burn tokens (requires MintAndBurn modality, caller must be owner) |

## Raw (Low-Level) Methods

These bypass permission checks — use inside your module's entry points where you
enforce your own authorization:

| Method | Description |
|---|---|
| `raw_transfer(sender: &Address, recipient: &Address, amount: &U256)` | Transfer without permission checks |
| `raw_mint(owner: &Address, amount: &U256)` | Mint without modality/badge checks |
| `raw_burn(owner: &Address, amount: &U256)` | Burn without modality/badge checks |

## Errors

| Variant | Code | Description |
|---|---|---|
| `InsufficientBalance` | 60001 | Sender balance too low |
| `InsufficientAllowance` | 60002 | Spender allowance too low |
| `CannotTargetSelfUser` | 60003 | Cannot transfer/approve to self |

## Events

| Event | Fields | When |
|---|---|---|
| `Mint` | `recipient: Address, amount: U256` | Tokens minted |
| `Burn` | `owner: Address, amount: U256` | Tokens burned |
| `Transfer` | `sender: Address, recipient: Address, amount: U256` | Direct transfer |
| `TransferFrom` | `spender: Address, owner: Address, recipient: Address, amount: U256` | Allowance-based transfer |
| `SetAllowance` | `owner: Address, spender: Address, allowance: U256` | Allowance set via `approve` |
| `IncreaseAllowance` | `owner: Address, spender: Address, allowance: U256, inc_by: U256` | Allowance increased |
| `DecreaseAllowance` | `owner: Address, spender: Address, allowance: U256, decr_by: U256` | Allowance decreased |

## Delegation Pattern

Use `delegate!` to expose CEP-18 methods on your wrapper contract without manually
forwarding each call:

```rust
#[odra::module]
impl MyToken {
    delegate! {
        to self.token {
            fn name(&self) -> String;
            fn symbol(&self) -> String;
            fn decimals(&self) -> u8;
            fn total_supply(&self) -> U256;
            fn balance_of(&self, address: &Address) -> U256;
            fn allowance(&self, owner: &Address, spender: &Address) -> U256;
            fn approve(&mut self, spender: &Address, amount: &U256);
            fn decrease_allowance(&mut self, spender: &Address, decr_by: &U256);
            fn increase_allowance(&mut self, spender: &Address, inc_by: &U256);
            fn transfer(&mut self, recipient: &Address, amount: &U256);
            fn transfer_from(&mut self, owner: &Address, recipient: &Address, amount: &U256);
        }
    }
}
```

## Full Example: Self-Governing Token with Voting

This example wraps `Cep18` with a democratic governance mechanism where token holders
vote on minting proposals.

### Types and Errors

```rust
use odra::{casper_types::U256, prelude::*};
use odra_modules::cep18_token::Cep18;

#[odra::odra_type]
struct Ballot {
    voter: Address,
    choice: bool,
    amount: U256,
}

#[odra::odra_error]
pub enum GovernanceError {
    VoteAlreadyOpen = 0,
    NoVoteInProgress = 1,
    VoteNotYetEnded = 2,
    VoteEnded = 3,
    OnlyTokenHoldersCanPropose = 4,
}
```

### OurToken Contract

```rust
#[odra::module(errors = GovernanceError)]
pub struct OurToken {
    token: SubModule<Cep18>,
    proposed_mint: Var<(Address, U256)>,
    votes: List<Ballot>,
    is_vote_open: Var<bool>,
    vote_end_time: Var<u64>,
}

#[odra::module]
impl OurToken {
    pub fn init(&mut self, name: String, symbol: String, decimals: u8, initial_supply: U256) {
        self.token.init(symbol, name, decimals, initial_supply, vec![], vec![], None);
    }

    // Delegate standard CEP-18 interface
    delegate! {
        to self.token {
            fn name(&self) -> String;
            fn symbol(&self) -> String;
            fn decimals(&self) -> u8;
            fn total_supply(&self) -> U256;
            fn balance_of(&self, address: &Address) -> U256;
            fn allowance(&self, owner: &Address, spender: &Address) -> U256;
            fn approve(&mut self, spender: &Address, amount: &U256);
            fn decrease_allowance(&mut self, spender: &Address, decr_by: &U256);
            fn increase_allowance(&mut self, spender: &Address, inc_by: &U256);
            fn transfer(&mut self, recipient: &Address, amount: &U256);
            fn transfer_from(&mut self, owner: &Address, recipient: &Address, amount: &U256);
        }
    }

    /// Burn tokens — caller must be the owner of the tokens.
    pub fn burn(&mut self, owner: &Address, amount: &U256) {
        self.token.assert_caller(owner);
        self.token.raw_burn(owner, amount);
    }

    /// Propose minting new tokens. Only token holders can propose.
    pub fn propose_new_mint(&mut self, account: Address, amount: U256) {
        if self.is_vote_open.get_or_default() {
            self.env().revert(GovernanceError::VoteAlreadyOpen);
        }
        if self.balance_of(&self.env().caller()) == U256::zero() {
            self.env().revert(GovernanceError::OnlyTokenHoldersCanPropose);
        }
        self.proposed_mint.set((account, amount));
        self.is_vote_open.set(true);
        // Vote window: 10 minutes
        self.vote_end_time.set(self.env().get_block_time() + 10 * 60 * 1000);
    }

    /// Cast a vote by staking tokens.
    pub fn vote(&mut self, choice: bool, amount: U256) {
        self.assert_vote_in_progress();
        let voter = self.env().caller();
        let contract = self.env().self_address();
        // Stake tokens by transferring to the contract
        self.token.transfer(&contract, &amount);
        self.votes.push(Ballot { voter, choice, amount });
    }

    /// Count votes after the voting period ends.
    pub fn tally(&mut self) {
        if !self.is_vote_open.get_or_default() {
            self.env().revert(GovernanceError::NoVoteInProgress);
        }
        let finish_time = self
            .vote_end_time
            .get_or_revert_with(GovernanceError::NoVoteInProgress);
        if self.env().get_block_time() < finish_time {
            self.env().revert(GovernanceError::VoteNotYetEnded);
        }

        let mut yes_votes = U256::zero();
        let mut no_votes = U256::zero();
        let contract = self.env().self_address();

        // Return staked tokens and count votes
        while let Some(vote) = self.votes.pop() {
            if vote.choice {
                yes_votes += vote.amount;
            } else {
                no_votes += vote.amount;
            }
            self.token.raw_transfer(&contract, &vote.voter, &vote.amount);
        }

        // Mint if vote passes
        if yes_votes > no_votes {
            let (account, amount) = self
                .proposed_mint
                .get_or_revert_with(GovernanceError::NoVoteInProgress);
            self.token.raw_mint(&account, &amount);
        }

        self.is_vote_open.set(false);
    }

    fn assert_vote_in_progress(&self) {
        if !self.is_vote_open.get_or_default() {
            self.env().revert(GovernanceError::NoVoteInProgress);
        }
        let finish_time = self
            .vote_end_time
            .get_or_revert_with(GovernanceError::NoVoteInProgress);
        if self.env().get_block_time() > finish_time {
            self.env().revert(GovernanceError::VoteEnded);
        }
    }
}
```

### Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use odra::host::Deployer;

    #[test]
    fn it_works() {
        let env = odra_test::env();
        let init_args = OurTokenInitArgs {
            name: "OurToken".to_string(),
            symbol: "OT".to_string(),
            decimals: 0,
            initial_supply: U256::from(1_000u64),
        };
        let mut token = OurToken::deploy(&env, init_args);

        // Deployer proposes minting 2000 tokens to account 1
        token.propose_new_mint(env.get_account(1), U256::from(2000));
        token.vote(true, U256::from(1000));

        // Tokens are staked during vote
        assert_eq!(token.balance_of(&env.get_account(0)), U256::zero());

        // Advance past voting window
        env.advance_block_time(60 * 11 * 1000);
        token.tally();

        // Tokens minted + stake returned
        assert_eq!(token.balance_of(&env.get_account(1)), U256::from(2000));
        assert_eq!(token.total_supply(), 3000.into());
        assert_eq!(token.balance_of(&env.get_account(0)), U256::from(1000));

        // Account 1 now has voting power for the next round
        env.set_caller(env.get_account(1));
        token.propose_new_mint(env.get_account(1), U256::from(2000));
        token.vote(true, U256::from(2000));

        // Deployer votes against
        env.set_caller(env.get_account(0));
        token.vote(false, U256::from(1000));

        env.advance_block_time(60 * 11 * 1000);
        token.tally();

        // Majority wins — tokens minted
        assert_eq!(token.balance_of(&env.get_account(1)), U256::from(4000));
    }
}
```

## CEP-18 Standard Reference

The underlying CEP-18 standard defines:

| Component | Description |
|---|---|
| **Entry points** | `name`, `symbol`, `decimals`, `total_supply`, `balance_of`, `allowance`, `transfer`, `transfer_from`, `approve`, `increase_allowance`, `decrease_allowance` |
| **Events** | `Mint`, `Burn`, `Transfer`, `TransferFrom`, `SetAllowance`, `IncreaseAllowance`, `DecreaseAllowance` |
| **Storage** | `name` (String), `symbol` (String), `decimals` (u8), `total_supply` (U256), `balances` dictionary, `allowances` dictionary |
| **Errors** | `InsufficientBalance` (60001), `InsufficientAllowance` (60002), `CannotTargetSelfUser` (60003) |
