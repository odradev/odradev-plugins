# CEP-95 NFT Standard

Odra implements the CEP-95 NFT Standard through the `odra_modules::cep95::Cep95` module.
Use it as a `SubModule` to add NFT capabilities to any contract.

## Quick Start

```rust
use odra::prelude::*;
use odra::casper_types::{U256, U512};
use odra_modules::cep95::{Cep95, CEP95Interface};

#[odra::module]
pub struct MyNft {
    token: SubModule<Cep95>,
}

#[odra::module]
impl MyNft {
    pub fn init(&mut self, name: String, symbol: String) {
        self.token.init(name, symbol);
    }

    pub fn mint(&mut self, to: Address, token_id: U256) {
        self.token.raw_mint(to, token_id, Default::default());
    }

    pub fn owner_of(&self, token_id: U256) -> Option<Address> {
        self.token.owner_of(token_id)
    }
}
```

## Cep95 SubModule Fields

The `Cep95` module contains these submodules (accessible as public fields):

| Field | Type | Description |
|---|---|---|
| `name` | `SubModule<Cep95Name>` | Token collection name |
| `symbol` | `SubModule<Cep95Symbol>` | Token collection symbol |
| `balances` | `SubModule<Cep95Balances>` | Owner balance mappings |
| `owners` | `SubModule<Cep95Owners>` | Token-to-owner mappings |
| `approvals` | `SubModule<Cep95Approvals>` | Per-token approval mappings |
| `operators` | `SubModule<Cep95Operators>` | Operator (approve-all) mappings |
| `metadata` | `SubModule<Cep95Metadata>` | Token metadata storage |

## CEP95Interface Methods

These methods are available on the `Cep95` submodule via the `CEP95Interface` trait:

| Method | Returns | Description |
|---|---|---|
| `name()` | `String` | Collection name |
| `symbol()` | `String` | Collection symbol |
| `balance_of(owner: Address)` | `U256` | Number of NFTs owned |
| `owner_of(token_id: U256)` | `Option<Address>` | Owner of a token |
| `approve(spender: Address, token_id: U256)` | | Approve an address to transfer a specific token |
| `revoke_approval(token_id: U256)` | | Revoke approval for a token |
| `approved_for(token_id: U256)` | `Option<Address>` | Get approved address for a token |
| `approve_for_all(operator: Address)` | | Approve operator for all caller's tokens |
| `revoke_approval_for_all(operator: Address)` | | Revoke operator approval |
| `is_approved_for_all(owner, operator)` | `bool` | Check if operator is approved for all |
| `transfer_from(from, to, token_id)` | | Transfer without recipient validation |
| `safe_transfer_from(from, to, token_id, data)` | | Transfer with recipient contract callback |
| `token_metadata(token_id: U256)` | `Vec<(String, String)>` | Get metadata key-value pairs |

## Raw (Low-Level) Methods

These bypass access control — use them inside your module's entry points where
you enforce your own authorization logic:

| Method | Description |
|---|---|
| `raw_mint(to: Address, token_id: U256, metadata: Vec<(String, String)>)` | Mint a new token |
| `raw_burn(token_id: U256)` | Permanently remove a token |
| `raw_transfer(to: Address, token_id: U256) -> Address` | Transfer without approval checks; returns previous owner |
| `clear_approval(token_id: &U256)` | Remove approval for a token |
| `set_metadata(token_id: U256, metadata: Vec<(String, String)>)` | Replace all metadata |
| `update_metadata(token_id: U256, metadata: Vec<(String, String)>)` | Merge metadata (update existing keys, add new) |
| `exists(token_id: &U256) -> bool` | Check if a token exists |
| `assert_exists(token_id: &U256)` | Revert with `InvalidTokenId` if token doesn't exist |

## Errors

| Variant | Code | Description |
|---|---|---|
| `ValueNotSet` | 40000 | A required value is not set |
| `TransferFailed` | 40001 | Transfer failed |
| `NotAnOwnerOrApproved` | 40002 | Caller is not owner or approved |
| `ApprovalToCurrentOwner` | 40003 | Cannot approve the current owner |
| `ApproveToCaller` | 40004 | Cannot approve the caller |
| `InvalidTokenId` | 40005 | Token ID does not exist |
| `TokenAlreadyExists` | 40006 | Token with this ID already exists |

## Events

The module emits these events automatically:

| Event | Fields | When |
|---|---|---|
| `Mint` | token, owner | Token is minted |
| `Burn` | token | Token is burned |
| `Transfer` | token, from, to | Token is transferred |
| `Approval` | token, owner, spender | Token approval granted |
| `RevokeApproval` | token | Token approval revoked |
| `ApprovalForAll` | owner, operator | Operator approved for all |
| `RevokeApprovalForAll` | owner, operator | Operator approval revoked |
| `MetadataUpdate` | token | Metadata created or updated |

## Metadata

Token metadata is stored as `Vec<(String, String)>` key-value pairs.

```rust
// Mint with metadata
let metadata = vec![
    ("name".to_string(), "My NFT #1".to_string()),
    ("image".to_string(), "https://example.com/nft1.png".to_string()),
];
self.token.raw_mint(owner, token_id, metadata);

// Read metadata
let meta = self.token.token_metadata(token_id);

// Update metadata (merges with existing)
let updates = vec![
    ("description".to_string(), "Updated description".to_string()),
];
self.token.update_metadata(token_id, updates);

// Replace all metadata
self.token.set_metadata(token_id, new_metadata);
```

## Approval & Transfer Patterns

### Direct Transfer (owner calls)

```rust
// Owner transfers their own token
self.token.transfer_from(owner, recipient, token_id);
```

### Approved Transfer (third-party calls)

```rust
// Step 1: Owner approves a spender
self.token.approve(spender, token_id);

// Step 2: Spender transfers the token
self.token.transfer_from(owner, recipient, token_id);
```

### Operator Pattern (approve for all tokens)

```rust
// Owner approves an operator for all their tokens
self.token.approve_for_all(operator);

// Operator can now transfer any of the owner's tokens
self.token.transfer_from(owner, recipient, any_token_id);
```

### Safe Transfer (with receiver callback)

```rust
// Transfer with callback validation — reverts if recipient contract
// does not implement the CEP95Receiver interface
self.token.safe_transfer_from(from, to, token_id, None);
```

## Full Example: Ticket Office with Operator Pattern

This example shows a real-world NFT use case combining ownership, minting, approvals,
cross-contract calls, payable entry points, events, and errors.

### Types and Events

```rust
use odra::prelude::*;
use odra::casper_types::{U256, U512};
use odra_modules::access::Ownable;
use odra_modules::cep95::{Cep95, CEP95Interface};

pub type TicketId = U256;

#[odra::odra_type]
pub enum TicketStatus {
    Available,
    Sold,
}

#[odra::odra_type]
pub struct TicketInfo {
    event_name: String,
    price: U512,
    status: TicketStatus,
}

#[odra::event]
pub struct OnTicketIssue {
    ticket_id: TicketId,
    event_name: String,
    price: U512,
}

#[odra::event]
pub struct OnTicketSell {
    ticket_id: TicketId,
    buyer: Address,
}

#[odra::odra_error]
pub enum Error {
    TicketNotAvailableForSale = 200,
    InsufficientFunds = 201,
    InvalidTicketId = 202,
    TicketDoesNotExist = 203,
    MissingOperator = 204,
    Unauthorized = 205,
}
```

### TicketOffice Contract

```rust
#[odra::module(
    events = [OnTicketIssue, OnTicketSell],
    errors = Error
)]
pub struct TicketOffice {
    token: SubModule<Cep95>,
    ownable: SubModule<Ownable>,
    tickets: Mapping<TicketId, TicketInfo>,
    token_id_counter: Var<TicketId>,
    total_supply: Var<u64>,
    operator: Var<Address>,
}

#[odra::module]
impl TicketOffice {
    pub fn init(&mut self, collection_name: String, collection_symbol: String, total_supply: u64) {
        let caller = self.env().caller();
        self.ownable.init(caller);
        self.token.init(collection_name, collection_symbol);
    }

    pub fn register_operator(&mut self, operator: Address) {
        let caller = self.env().caller();
        self.ownable.assert_owner(&caller);
        TicketOperatorContractRef::new(self.env(), operator)
            .register(self.env().self_address());
        self.operator.set(operator);
    }

    pub fn issue_ticket(&mut self, event_name: String, price: U512) {
        let env = self.env();
        let caller = env.caller();
        self.ownable.assert_owner(&caller);

        let ticket_id = self.token_id_counter.get_or_default();
        self.token.mint(caller, ticket_id, Default::default());

        self.tickets.set(
            &ticket_id,
            TicketInfo {
                event_name: event_name.clone(),
                price,
                status: TicketStatus::Available,
            },
        );
        self.token_id_counter.set(ticket_id + 1);

        // Approve the operator to transfer on behalf of the owner
        let operator = self.operator();
        self.token.approve(operator, ticket_id);

        env.emit_event(OnTicketIssue { ticket_id, event_name, price });
    }

    pub fn buy_ticket(&mut self, ticket_id: TicketId, buyer: Address, value: U512) {
        let env = self.env();
        let owner = self.ownable.get_owner();
        let caller = env.caller();

        if !self.is_operator(caller) {
            env.revert(Error::Unauthorized);
        }

        let mut ticket = self
            .tickets
            .get(&ticket_id)
            .unwrap_or_revert_with(&env, Error::TicketDoesNotExist);

        if ticket.status != TicketStatus::Available {
            env.revert(Error::TicketNotAvailableForSale);
        }

        if value < ticket.price {
            env.revert(Error::InsufficientFunds);
        }

        self.token.transfer_from(owner, buyer, ticket_id);

        ticket.status = TicketStatus::Sold;
        self.tickets.set(&ticket_id, ticket);

        env.emit_event(OnTicketSell { ticket_id, buyer });
    }

    fn is_operator(&self, caller: Address) -> bool {
        Some(caller) == self.operator.get()
    }

    fn operator(&self) -> Address {
        self.operator
            .get()
            .unwrap_or_revert_with(&self.env(), Error::MissingOperator)
    }
}
```

### TicketOperator (Intermediary Contract)

```rust
use crate::token::{TicketId, TicketOfficeContractRef};
use odra::prelude::*;
use odra::casper_types::{U256, U512};
use odra::ContractRef;

#[odra::odra_error]
pub enum Error {
    UnknownTicketOffice = 300,
}

#[odra::module(errors = Error)]
pub struct TicketOperator {
    ticket_office_address: Var<Address>,
}

#[odra::module]
impl TicketOperator {
    pub fn register(&mut self, ticket_office_address: Address) {
        self.ticket_office_address.set(ticket_office_address);
    }

    #[odra(payable)]
    pub fn buy_ticket(&mut self, ticket_id: TicketId) {
        let env = self.env();
        let buyer = env.caller();
        let value = env.attached_value();

        let center = self
            .ticket_office_address
            .get()
            .unwrap_or_revert_with(&env, Error::UnknownTicketOffice);

        let mut ticket_contract = TicketOfficeContractRef::new(env, center);
        ticket_contract.buy_ticket(ticket_id, buyer, value);
    }

    pub fn balance_of(&self) -> U512 {
        self.env().self_balance()
    }
}
```

### Tests

```rust
use odra::{
    casper_types::U512,
    host::{Deployer, HostRef, NoArgs},
    prelude::*,
};
use crate::{
    ticket_operator::TicketOperatorHostRef,
    token::{Error, TicketId, TicketOfficeContractRef, TicketOfficeInitArgs},
};

#[test]
fn it_works() {
    let env = odra_test::env();
    let init_args = TicketOfficeInitArgs {
        collection_name: "Ticket".to_string(),
        collection_symbol: "T".to_string(),
        total_supply: 100,
    };

    let operator = TicketOperator::deploy(&env, NoArgs);
    let mut ticket_office = TicketOfficeContractRef::deploy(&env, init_args);
    ticket_office.register_operator(operator.address().clone());

    ticket_office.issue_ticket("Ev".to_string(), U512::from(100));
    ticket_office.issue_ticket("Ev".to_string(), U512::from(50));

    let buyer = env.get_account(1);
    env.set_caller(buyer);

    // Insufficient funds
    assert_eq!(
        operator.with_tokens(U512::from(50)).try_buy_ticket(0.into()),
        Err(Error::InsufficientFunds.into())
    );

    // Successful purchase
    assert_eq!(
        operator.with_tokens(U512::from(100)).try_buy_ticket(0.into()),
        Ok(())
    );

    // Already sold
    assert_eq!(
        operator.with_tokens(U512::from(100)).try_buy_ticket(0.into()),
        Err(Error::TicketNotAvailableForSale.into())
    );

    // Operator accumulated funds
    assert_eq!(operator.balance_of(), U512::from(150));
}
```
