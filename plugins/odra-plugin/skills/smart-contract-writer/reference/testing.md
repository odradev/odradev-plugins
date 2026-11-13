# Odra Testing Guide

## Three Backends

### OdraVM (default — use for unit tests)

Fast in-memory VM. No blockchain, no WASM. Runs in milliseconds.

```bash
cargo odra test           # from the project root
```

Use OdraVM for: all contract logic tests, event assertions, error assertions,
caller-switching tests, balance tests, factories (since 2.10).

### CasperVM (use for integration tests)

Full Casper execution engine. Compiles contracts to WASM and runs them through
the real Casper runtime. Much slower than OdraVM but catches WASM-specific issues.

```bash
cargo odra test -b casper        # builds the wasm first
cargo odra test -b casper -s     # skips the build, reuses wasm/
```

Use CasperVM for: pre-deployment validation, testing contracts that interact
with Casper-specific types, verifying WASM compilation succeeds.

### Livenet (use for deployment)

Real Casper blockchain node. Requires a running node (NCTL locally or testnet/mainnet).
Not used for automated tests — used via the project's CLI binary (`bin/cli.rs`):

```bash
cargo odra build
cargo run --bin <project>_cli -- deploy
```

No `--features livenet` is needed in a generated project; `odra-cli` brings the livenet backend.
Use livenet for: deploying to nctl/testnet/mainnet, running scenarios against a live node.

## Switching Backends

`cargo odra test -b casper` sets the `ODRA_BACKEND` environment variable; `odra_test::env()` reads
it and returns the matching backend.

A test can also pin its backend (2.10):

```rust
let env = odra_test::odra_env();    // always OdraVM
let env = odra_test::casper_env();  // always CasperVM (needs the wasm)
```

Use `odra_env()` for a module that is only a building block of other contracts and is not in
`Odra.toml`: there is no wasm for it, so under `-b casper` `deploy` would fail.

## Setting Up a Test

```rust
#[cfg(test)]
mod tests {
    use super::{MyContract, MyContractInitArgs};
    use odra::host::Deployer;

    #[test]
    fn my_test() {
        let env = odra_test::env();
        let mut contract = MyContract::deploy(&env, MyContractInitArgs {
            initial_value: 42,
        });
        assert_eq!(contract.get_value(), 42);
    }
}
```

For contracts with no constructor, use `NoArgs`:

```rust
use odra::host::{Deployer, NoArgs};
let contract = MyContract::deploy(&env, NoArgs);
```

A deploy whose `init` reverts: `MyContract::try_deploy(&env, args)` returns the contract's error on
every backend (livenet included since 2.10).

## `HostEnv` — Test Environment API

```rust
let env = odra_test::env();
```

| Method | Description |
|---|---|
| `env.get_account(n)` | Returns the n-th test account (`Address`). Account 0 is the default caller. |
| `env.set_caller(address)` | Change the active caller for subsequent calls |
| `env.advance_block_time(diff)` | Advance the block time; `diff` is a `core::time::Duration` or a number of milliseconds |
| `env.block_time()` / `block_time_secs()` | Current block time in ms / s |
| `env.balance_of(&addressable)` | Native token balance of a contract or account (`U512`) |
| `env.transfer(to, amount) -> OdraResult<()>` | Native transfer from the caller; works on CasperVM since 2.10 |
| `env.set_gas(motes)` | Gas for the next calls (required on livenet, ignored by the VMs) |
| `env.emitted_event(&contract, event)` | `true` if the event was emitted (event by value) |
| `env.emitted_native_event(&contract, event)` | Same for native events |
| `env.emitted(&contract, "EventName")` | `true` if any event with that name was emitted |
| `env.events_count(&contract)` | Number of events emitted by the contract |
| `contract.last_call()` | Result of the last call: `emitted(..)`, `emitted_event(..)`, events, gas |
| `env.take_snapshot()` / `env.restore_snapshot()` | Save and restore the whole VM state (2.10) |
| `env.concurrently(items, \|env, item\| ..)` | Run a closure per item; worker threads on livenet, sequential on the VMs (2.10) |
| `env.gas_report()` / `env.last_call_gas_cost()` | Gas used, on every backend |
| `env.get_named_value(&addr, "name")`, `get_dictionary_value(..)`, `get_storage_value(..)` | Raw storage reads (2.10) |

## Calling Entry Points

```rust
// Normal call — panics on revert
contract.increment();
let value = contract.get();

// Try call — returns Result, does not panic on revert
let result = contract.try_increment();
let err = contract.try_restricted_action().unwrap_err();
```

`#[odra(offchain)]` functions are on the `HostRef` like any getter (`book.all_balances()`,
`book.try_all_balances()`), on every backend.

## Switching Callers

```rust
let alice = env.get_account(0);
let bob = env.get_account(1);

env.set_caller(alice);
let mut contract = MyContract::deploy(&env, NoArgs);

env.set_caller(bob);
// subsequent calls are made as bob
contract.some_action();
```

## Native Token Transfers (Payable Calls)

```rust
// Send 100 motes to a payable entry point
contract.with_tokens(U512::from(100)).deposit();

// Check contract balance
let balance = env.balance_of(&contract);
assert_eq!(balance, U512::from(100));
```

## Advancing Time

```rust
use core::time::Duration;

env.advance_block_time(Duration::from_secs(60));  // states the unit itself
env.advance_block_time(1000);                     // a number is milliseconds
let time = contract.get_timestamp();              // reflects the new block time
```

## Snapshots — one setup, many scenarios (2.10)

```rust
let env = odra_test::env();
let mut token = OwnedToken::deploy(&env, args);
// ... configure the contracts ...
env.take_snapshot();

// Scenario A
token.transfer(&alice, &U256::from(100));
assert_eq!(token.balance_of(&alice), U256::from(100));

// Back to the starting point: scenario A never happened.
env.restore_snapshot();
assert_eq!(token.balance_of(&alice), U256::zero());
```

A snapshot covers storage, CSPR balances, events, block time and the contracts themselves (a
contract deployed or upgraded after the snapshot is gone, or back to its old code). Only the last
snapshot is kept. The caller set with `set_caller` and the gas report are not part of it. Works on
OdraVM and CasperVM; livenet panics.

## Testing an upgrade

Install the first version upgradable — a plain `deploy` is locked on CasperVM and livenet (OdraVM
does not model the lock, so the test would pass there and fail with
`A locked contract cannot be upgraded` under `-b casper`):

```rust
use odra::host::{Deployer, HostRef, InstallConfig, NoArgs};

let env = odra_test::env();
let mut v1 = Counter::deploy_with_cfg(&env, CounterInitArgs { start: 10 }, InstallConfig::upgradable::<Counter>());
v1.increment();

// `upgrade(&mut self, registry: Address)` in the new code => CounterUpgradeArgs { registry }
let v2 = Counter::try_upgrade(&env, v1.address(), CounterUpgradeArgs { registry: registry.address() }).unwrap();
assert_eq!(v2.get(), 11);                       // storage survived
assert_eq!(v2.get_dapp_registry(), registry.address());
```

`try_upgrade` is the host-side call and returns `OdraResult<HostRef>`; `Counter::upgrade(..)` would
resolve to your own entry point. In a unit test the "old" and "new" versions are the same code, so
the test checks the migration logic, not the layout change itself — keep new fields appended.

## Loading and addressing deployed contracts

```rust
use odra::host::HostRefLoader;
let token = MyToken::load(&env, address);              // works on every backend since 2.10
let child = CounterHostRef::new(address, env.clone()); // same thing, from a factory's child address
```

Both register the contract with the environment, so getters, events and offchain functions work for
a contract known only by its address (a factory child, a contract someone else deployed).

## Asserting Events

See `events.md` for the full events API.

```rust
assert!(env.emitted_event(&contract, MyEvent {
    field: expected_value,
}));
```

## Asserting Errors

See `errors.md` for error definition. Use `.try_method()`:

```rust
let err = contract.try_restricted_action().unwrap_err();
assert_eq!(err, MyError::Unauthorized.into());
```

## Debug output from a contract

`self.env().debug(message)` prints on the host. OdraVM always prints; CasperVM only when the
contract crate enables the `test-support` feature of `odra`
(`odra = { version = "2.10.0", features = ["test-support"] }`); run with
`cargo odra test -b casper -- --nocapture` (cargo-odra 0.2.1+; on 0.2.0 `ODRA_BACKEND=casper cargo test -- --nocapture`). Production wasm is built without the feature. A raw
`panic!`/`unwrap` in contract code prints the standard Rust message too (since 2.10 OdraVM no longer
swallows it) and comes back as `VmError::Panic`.

## What OdraVM does and does not model

- A reverted call is rolled back as a whole, like Casper: storage, balances, deployed contracts,
  the code of a failed upgrade, and the events (also of nested calls). Event counts and
  `last_call()` never see them.
- Factories work (`new_contract`, `upgrade_child_contract`, `batch_upgrade_child_contract`), with
  a stand-in access URef and a simplified upgrade permission check (direct caller == factory deployer).
- A plain Rust panic in a contract rolls nothing back, and a reverted deploy still uses up an
  address.
- Package locking is not modelled: a contract deployed without `InstallConfig::upgradable` can be
  upgraded on OdraVM, but not on CasperVM or livenet.
- Gas is not metered; only CasperVM and livenet report real costs.

## Getting a Contract's Env Reference

If you need the env from a deployed contract ref:

```rust
let env = contract.env();
```
