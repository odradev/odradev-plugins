# Odra Contract Anatomy

## The `#[odra::module]` Macro

Apply `#[odra::module]` to both the struct and its impl block. The struct's fields are
on-chain storage. Every `pub fn` in the impl block becomes an entry point (callable on-chain).

```rust
use odra::prelude::*;

#[odra::module]
pub struct Counter {
    value: Var<u32>,
}

#[odra::module]
impl Counter {
    pub fn init(&mut self, start: u32) {
        self.value.set(start);
    }

    pub fn increment(&mut self) {
        let v = self.value.get_or_default();
        self.value.set(v + 1);
    }

    pub fn get(&self) -> u32 {
        self.value.get_or_default()
    }
}
```

## What the Macro Generates

For a contract named `Counter`, the macro generates:

| Generated type | Purpose |
|---|---|
| `CounterHostRef` | Host-side proxy — all entry points as Rust methods |
| `CounterInitArgs` | Struct built from `init`'s parameters (if `init` exists) |
| `CounterContractRef` | Used for cross-contract calls (see Cross-Contract Calls section) |
| `EntryPointsCaller` | Internal bridge from host call to contract function |

## Module Attributes

The struct attribute accepts optional arguments:

```rust
#[odra::module(events = [TransferEvent, ApprovalEvent], errors = Error, name = "MyToken", version = "1.0.0")]
pub struct Token { ... }
```

- `events` — list of event types emitted by this module (for schema generation; submodules' events
  are collected automatically)
- `errors` — the error enum for this module (for schema generation)
- `name` — the contract's name in the schema **and**, since 2.10, the named key its package hash is
  stored under (`<name>_package_hash`; without `name`: `<StructName>_package_hash`)
- `version` — the contract version in the schema
- `layout` — a custom storage layout (rarely needed)

All of them belong on the **struct**. On an impl block they are a compile error since 2.10 (they
used to be silently ignored); the only impl-block argument is `factory = on` (see `factory.md`).

### Reserved names

An entry point cannot be named `new`, `env`, `address`, `new_contract`, `upgrade_child_contract` or
`batch_upgrade_child_contract`, and its arguments cannot be named `gas` or `attached_value`. Private
helper functions may use any name. Everything else works since 2.10, including arguments called
`contract`, `env` or `result` (the generated code prefixes its own locals with `__odra_`).

## odra::prelude

Always import `odra::prelude::*` to get all necessary traits and types for contracts.
When `use odra::prelude::*` is present, there's no need to import: `Address`, `Var`, `Mapping`,
`List`, `Sequence`, `Module`, `SubModule`, `External`, `ContractEnv`, `OdraError`,
`ExecutionError`, `UnwrapOrRevert`, `String`, `Vec`, `vec!`, `Rc`, `RefCell`, `Box`,
`BTreeMap`, `format!`, `ToString`, `ToOwned`, `FromStr`, or `casper_event_standard`.

## Number Types

Use `u32`, `u64`, `i32`, `i64` for general integers. For token amounts, use `U256` or `U512`
from `odra::casper_types` to avoid overflow issues. `U256` is common for fungible tokens; `U512` is
the type of CSPR amounts (motes).

`U256::from(..)` cannot run at compile time. For constants the prelude has `const fn u256(n: u128)`
and `u512(n: u128)` (2.10 for `u512`):

```rust
use odra::prelude::*;

const ONE_TOKEN: U256 = u256(1_000_000_000_000_000_000);
const MIN_DEPOSIT: U512 = u512(1_000_000_000); // 1 CSPR in motes
```

Arithmetic on these types is **unchecked** from Odra's point of view: an overflow is a Rust panic
(`VmError::Panic`), not a revert. Check or use `checked_*` and revert with your own error.

## Storage Types

All storage fields are declared on the contract struct. They read from and write to
the blockchain's key-value store — not in-memory. Access them via `self.field_name`.

### `Var<T>` — single value

```rust
name: Var<String>,
count: Var<u32>,
owner: Var<Address>,
```

| Method | Description |
|---|---|
| `self.name.set(value)` | Write a value |
| `self.name.get()` | Returns `Option<T>` |
| `self.name.get_or_default()` | Returns `T`, uses `Default::default()` if unset |
| `self.name.get_or_revert_with(err)` | Returns `T`, reverts if unset |
| `self.name.is_none()` | Returns `true` if no value has been set |

**Common pattern — initialize in `init`, update in entry points:**

```rust
pub fn init(&mut self, name: String) {
    self.name.set(name);
}

pub fn rename(&mut self, new_name: String) {
    self.name.set(new_name);
}

pub fn get_name(&self) -> String {
    self.name.get_or_default()
}
```

### `Mapping<K, V>` — key-value store

```rust
balances: Mapping<Address, U256>,
visits: Mapping<String, u32>,
```

| Method | Description |
|---|---|
| `self.balances.set(&key, value)` | Write a value for a key |
| `self.balances.get(&key)` | Returns `Option<V>` |
| `self.balances.get_or_default(&key)` | Returns `V`, uses `Default::default()` if unset |
| `self.balances.get_or_revert_with(&key, err)` | Returns `V`, reverts if unset |
| `self.balances.add(&key, n)` / `subtract(&key, n)` | Arithmetic on numeric values |
| `self.nested.module(&key)` | For `Mapping<K, SomeModule>`: a `SubModule<SomeModule>` scoped to the key |
| `self.lists.list(&key)` | For `Mapping<K, List<T>>`: the `List<T>` of that key (2.10) — a growable collection per key |

```rust
walks: Mapping<Address, List<u32>>,
// ...
pub fn walk_the_dog(&mut self, owner: &Address, length: u32) {
    self.walks.list(owner).push(length);
}
pub fn walks_amount(&self, owner: &Address) -> u32 {
    self.walks.list(owner).len()
}
```

A `List` can be a mapping value, never a mapping key.

**Common pattern:**

```rust
pub fn add_visit(&mut self, name: &String) {
    let count = self.visits.get_or_default(name);
    self.visits.set(name, count + 1);
}

pub fn visit_count(&self, name: &String) -> u32 {
    self.visits.get_or_default(name)
}
```

### `List<T>` — append-only list

```rust
walks: List<u32>,
items: List<Address>,
```

| Method | Description |
|---|---|
| `self.walks.push(value)` | Append a value |
| `self.walks.len()` | Number of elements (`u32`) |
| `self.walks.iter()` | Iterator over values |
| `self.walks.pop()` | Remove and return last element (`Option<T>`) |

**Common pattern:**

```rust
pub fn add_walk(&mut self, distance: u32) {
    self.walks.push(distance);
}

pub fn total_distance(&self) -> u32 {
    self.walks.iter().sum()
}
```

### `Sequence<T>` — auto-incrementing counter

```rust
next_id: Sequence<u32>,
```

| Method | Description |
|---|---|
| `self.next_id.get_current_value()` | Read without incrementing |
| `self.next_id.next_value()` | Increment and return new value |

**Common pattern — generating unique IDs:**

```rust
pub fn create_item(&mut self) -> u32 {
    self.next_id.next_value()
}
```

### Cross-Contract Calls

Odra supports two cross-contract patterns:

1. **`External<T>` field** — stores a contract address as a field, calls it like a sub-field
2. **`ContractRef::new()`** — constructs a ref on the fly from an address (no storage field)

Both produce the same on-chain behavior. `External<T>` is cleaner when the address is
stored long-term; `ContractRef::new()` is useful for one-off or injected addresses.

#### Defining an External Contract Interface

Define the external contract's interface with `#[odra::external_contract]`:

```rust
#[odra::external_contract]
pub trait Token {
    fn balance_of(&self, owner: &Address) -> U256;
    fn transfer(&mut self, to: &Address, amount: &U256);
}
```

This generates a `TokenContractRef` type (for contracts) and a `TokenHostRef` (for tests and
scripts). Since 2.10 the `Token` trait itself is kept and both refs implement it, so it can be used
as a bound (`fn sum<T: Token>(t: &T)`) or implemented by one of your modules — do not declare the
trait a second time by hand (a 2.9 workaround; it is now a duplicate-definition error).

#### Helpers on both refs: `#[odra::ref_helpers]` (2.10)

A convenience function composed of entry point calls is often needed in a contract (on the
`ContractRef`) and in tests (on the `HostRef`). Write it once, in an inherent impl named after the
module or the external trait:

```rust
#[odra::ref_helpers]
impl Token {
    /// The tokens the token contract holds itself.
    pub fn own_balance(&self) -> U256 {
        self.balance_of(&self.contract_address())
    }
}
```

The block is copied into `impl TokenContractRef` and `impl TokenHostRef`. Helpers may use only what
both refs have: the entry points and `self.contract_address()` (the address the ref points at; the
`ContractAddress` trait from the prelude). A helper that calls a `&mut self` entry point takes
`&mut self` too.

#### Sending CSPR along a cross-contract call

`with_tokens` exists on a `ContractRef` as well; the amount comes from the calling contract's
balance and the target entry point must be `#[odra(payable)]`:

```rust
#[odra(payable)]
pub fn forward(&mut self, wallet: &Address) {
    let amount = self.env().attached_value();
    WalletContractRef::new(self.env(), *wallet).with_tokens(amount).deposit();
}
```

#### `External<T>` Field

Store the generated ref type in a contract field:

```rust
#[odra::module]
pub struct Wallet {
    token: External<TokenContractRef>,
}

#[odra::module]
impl Wallet {
    pub fn init(&mut self, token_address: Address) {
        self.token.set(token_address);
    }

    pub fn my_balance(&self) -> U256 {
        self.token.balance_of(&self.env().caller())
    }
}
```

#### `ContractRef::new()`

When you have the address but don't store it permanently:

```rust
use odra::ContractRef;

pub fn query_balance(&self, token_address: Address, owner: &Address) -> U256 {
    TokenContractRef::new(self.env(), token_address).balance_of(owner)
}
```

#### Mutable vs Immutable Calls

- Entry points that mutate state (`&mut self`) require the `ContractRef` to be `mut`
- Read-only entry points (`&self`) work on an immutable ref

```rust
// Mutable cross-contract call
TokenContractRef::new(self.env(), addr).transfer(&recipient, &amount);

// Read-only cross-contract call
let supply = TokenContractRef::new(self.env(), addr).total_supply();
```

#### Cross-Contract in Tests

Deploy both contracts, wire the address:

```rust
#[test]
fn test_wallet() {
    let env = odra_test::env();

    // Deploy the token first
    let token = MyToken::deploy(&env, MyTokenInitArgs {
        initial_supply: 1000.into(),
    });

    // Deploy wallet with token address
    let wallet = Wallet::deploy(&env, WalletInitArgs {
        token_address: token.address(),
    });

    assert_eq!(wallet.my_balance(), 1000.into());
}
```

## Entry Points

Only `pub fn` methods in the `#[odra::module]` impl block become entry points (callable
on-chain). Non-public functions are internal helpers only.

```rust
#[odra::module]
impl Counter {
    pub fn increment(&mut self) { ... }  // entry point
    pub fn get(&self) -> u32 { ... }     // entry point
    fn internal_helper(&self) { ... }    // not an entry point
}
```

### `&self` vs `&mut self`

- Use `&self` for read-only entry points (don't write to storage)
- Use `&mut self` for entry points that write to storage or emit events

### Return Types

```rust
pub fn get_count(&self) -> u32 { ... }         // returns value directly
pub fn maybe_value(&self) -> Option<String> { ... } // Option is valid
pub fn transfer(&mut self) { ... }              // () — no return needed
```

On-chain, return values are serialized via `casper_types`. Use types that implement
`CLTyped + ToBytes + FromBytes`: primitive integers, `bool`, `String`, `Address`,
`U256`, `U512`, `Vec<T>`, `Option<T>`, tuples, custom types with `#[odra::odra_type]`.

### Optional Arguments

Use `Maybe<T>` (Odra's optional argument type) for truly optional init/entry args:

```rust
pub fn init(&mut self, name: String, metadata: Maybe<String>) {
    if let Some(m) = metadata.into() {
        self.metadata.set(m);
    }
}
```

### Payable Entry Points

Mark an entry point with `#[odra(payable)]` to allow it to receive native CSPR tokens:

```rust
#[odra(payable)]
pub fn deposit(&mut self) {
    // self.env().self_balance() now includes the attached tokens
    let amount: U512 = self.env().attached_value();
}
```

Calling a payable entry point from a test:

```rust
contract.with_tokens(U512::from(100)).deposit();
```

Calling a non-payable entry point with tokens fails and refunds the tokens. `payable` on `init` or
`upgrade` is a compile error (2.10): a constructor can never receive tokens.

### Attribute checklist

`#[odra(..)]` takes `payable`, `non_reentrant` (reentrancy guard) and `offchain`; anything else, a
repeated flag, or `payable = true` is a compile error since 2.10.

### Offchain functions (`#[odra(offchain)]`, 2.10)

Some reads belong on the contract but must never be entry points: iterating a whole list,
aggregating many balances, building a report. On chain they would cost too much gas or not fit in a
transaction. `#[odra(offchain)]` keeps the function in the module but out of the deployed contract:
not a wasm entry point, not in the schema. It runs on the host against the contract's state — on
OdraVM, CasperVM and livenet alike — free and without size limit.

```rust
#[odra::module]
impl BalanceBook {
    pub fn balance_of(&self, owner: &Address) -> U256 {
        self.balances.get_or_default(owner)
    }

    /// Every holder with its balance: a loop over the whole list, fine on the host.
    #[odra(offchain)]
    pub fn all_balances(&self) -> Vec<(Address, U256)> {
        self.holders.iter().map(|h| (h, self.balance_of(&h))).collect()
    }
}
```

It is on the `HostRef` like any getter (`book.all_balances()`, `book.try_all_balances()`), and
odra-cli lists it under `contract <Name>` marked as offchain (no `--gas`). Rules: `&self` only (no
state change, no events, no transfers), a plain impl block (not a trait impl), not `payable` or
`non_reentrant`. It may call the contract's own functions and non-mutating entry points of other
contracts. Other contracts cannot call it — it is not on the `ContractRef`. Inside, `caller()` is
the account that called it; a revert comes back as the error from `try_*`.

## Constructor: `init`

The function named `init` is the constructor. It runs once at deploy time.
Its parameters become fields of the generated `<Name>InitArgs` struct.

```rust
// Generates: CounterInitArgs { initial_value: u32 }
pub fn init(&mut self, initial_value: u32) {
    self.value.set(initial_value);
}
```

Deploying with constructor args:

```rust
Counter::deploy(&env, CounterInitArgs { initial_value: 0 })
```

Contracts with no `init` function are deployed with `NoArgs`:

```rust
use odra::host::{Deployer, NoArgs};
Counter::deploy(&env, NoArgs)
```

## Accessing On-Chain Context: `self.env()`

Inside any entry point, `self.env()` returns a `ContractEnv` reference for accessing
on-chain context:

```rust
pub fn do_something(&mut self) {
    let caller = self.env().caller();             // Address: the account or contract right behind us
    let me = self.env().self_address();            // Address of this contract
    let now = self.env().get_block_time();         // u64 (milliseconds)
    let balance = self.env().self_balance();       // U512 (contract balance)
    let attached = self.env().attached_value();    // U512, in a payable entry point
    self.env().transfer_tokens(&caller, &amount);  // send native tokens
    self.env().emit_event(MyEvent { ... });        // emit event
    self.env().revert(MyError::SomeVariant);       // revert (never returns)
}
```

### Call stack (2.10)

`caller()` is the address right behind the contract. `call_stack()` returns every address from the
account that sent the transaction to the current contract, and `nth_caller(n)` walks it:
`nth_caller(0)` is `caller()`, `nth_caller(1)` the caller of the caller, `None` when the stack is
not that deep. Same on every backend, also in getters and offchain functions.

```rust
pub fn burn_for_origin(&mut self, amount: U256) {
    let env = self.env();
    // check the immediate caller first (tx.origin caveats apply to anything further up)
    self.assert_is_burner(&env.caller());
    let account = env.nth_caller(1).unwrap_or_revert_with(self, Error::NoOrigin);
    self.token.raw_burn(&account, &amount);
}
```

### Debug output (2.10)

`self.env().debug(format!("transfer of {amount}"))` prints on the host running the contract.
OdraVM always prints; CasperVM only when the contract crate enables the `test-support` feature of
`odra` (then run `cargo odra test -b casper -- --nocapture`); without the feature the call compiles
to nothing. Build production wasm without `test-support`.

## Upgrades

A contract deployed upgradable (`InstallConfig::upgradable`, the default of `load_or_deploy`) can be
replaced by a new version that implements `upgrade(&mut self, ...)`; its parameters become
`<Name>UpgradeArgs`. Entry points follow the new code; storage stays where it is and `upgrade` is
the place to migrate it (`init` is not called again). `upgrade` cannot be `payable`. In tests:
`NewVersion::try_upgrade(&env, address, args)`; on livenet: odra-cli's `upgrade` command.

## SubModules

Contracts can nest other modules as fields using `SubModule<T>`:

```rust
#[odra::module]
pub struct ManagedToken {
    ownable: SubModule<Ownable>,
    token: SubModule<Erc20>,
}
```

SubModule methods are called directly: `self.ownable.get_owner()`.
To forward entry points to a SubModule, use the `delegate!` macro.
