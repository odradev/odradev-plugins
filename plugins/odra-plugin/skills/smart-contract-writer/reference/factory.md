# Odra Factory Pattern

The factory pattern enables a contract to deploy, manage, and track child contract instances
on-chain. The parent contract acts as a centralized registry for all child contracts it creates.

## Enabling Factory Support

Add `factory=on` to the `#[odra::module]` attribute on both the struct and impl block
of the **child** contract (the contract that will be deployed by the factory):

```rust
use odra::prelude::*;

#[odra::module(factory=on)]
pub struct Counter {
    value: Var<u32>,
}

#[odra::module(factory=on)]
impl Counter {
    pub fn init(&mut self, value: u32) {
        self.value.set(value);
    }

    pub fn increment(&mut self) {
        self.value.set(self.value.get_or_default() + 1);
    }

    pub fn value(&self) -> u32 {
        self.value.get_or_default()
    }
}
```

## What `factory=on` Generates

For a contract named `Counter`, the macro generates a `CounterFactory` module with these
entry points:

| Method | Description |
|---|---|
| `new_contract(name, ...init_args)` | Deploy a new child contract instance. Returns `(Address, URef)` — the child's address and its access URef. |
| `upgrade_child_contract(...)` | Upgrade a single child contract to the latest WASM version. |
| `batch_upgrade_child_contract(...)` | Upgrade multiple child contracts in one call (gas-efficient). |

The factory is itself a regular `#[odra::module]` — deploy it with `NoArgs` since
it has no constructor of its own.

## Deploying Child Contracts

Call `new_contract` on the factory to deploy a child instance. The first argument is the
contract name (`String`), followed by the child's `init` parameters:

```rust
let (address, _access_uref) = factory_ref.new_contract(String::from("Counter"), 10);
```

The returned `Address` is the child contract's on-chain address. Use it to construct
a `HostRef` and interact with the child:

```rust
let mut counter_ref = CounterHostRef::new(address, env);
counter_ref.increment();
assert_eq!(counter_ref.value(), 11);
```

## Upgrading Child Contracts

The factory supports upgrading child contracts to new WASM versions:

- `upgrade_child_contract` — upgrade a single child contract
- `batch_upgrade_child_contract` — upgrade multiple children in one call, saving gas

Upgrade functions use `UpgradeArgs` which implements `Into<RuntimeArgs>` for seamless
parameter conversion.

## Testing a Factory

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use odra::host::{Deployer, NoArgs};

    #[test]
    fn test_factory() {
        let env = odra_test::env();

        // Deploy the factory
        let mut factory_ref = CounterFactory::deploy(&env, NoArgs);

        // Deploy a child contract via the factory
        let (address, _access_uref) = factory_ref.new_contract(String::from("Counter"), 10);

        // Interact with the child
        let mut counter_ref = CounterHostRef::new(address, env);
        counter_ref.increment();
        assert_eq!(counter_ref.value(), 11);
    }
}
```

## When to Use the Factory Pattern

- You need a contract that spawns multiple instances of another contract at runtime
- You want a centralized registry tracking all deployed child contracts
- You need to upgrade child contracts from the parent
